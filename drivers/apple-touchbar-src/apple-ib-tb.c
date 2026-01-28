// SPDX-License-Identifier: GPL-2.0
/*
 * Apple Touch Bar Driver
 *
 * Copyright (c) 2017-2018 Ronald Tschalär
 */

#define dev_fmt(fmt) "tb: " fmt

#include <linux/device.h>
#include <linux/hid.h>
#include <linux/input.h>
#include <linux/jiffies.h>
#include <linux/ktime.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/slab.h>
#include <linux/spinlock.h>
#include <linux/sysfs.h>
#include <linux/usb/ch9.h>
#include <linux/usb.h>
#include <linux/workqueue.h>

#include "apple-ibridge/apple-ibridge.h"

#define HID_UP_APPLE		0xff120000
#define HID_USAGE_MODE		(HID_UP_CUSTOM | 0x0004)
#define HID_USAGE_APPLE_APP	(HID_UP_APPLE  | 0x0001)
#define HID_USAGE_DISP		(HID_UP_APPLE  | 0x0021)

#define APPLETB_MAX_TB_KEYS	13	/* ESC, F1-F12 */

#define APPLETB_DEVID_KEYBOARD	0x01
#define APPLETB_DEVID_TOUCHPAD	0x02

#define APPLETB_FN_MODE_NORM	0
#define APPLETB_FN_MODE_FKEYS	1
#define APPLETB_FN_MODE_MAX	APPLETB_FN_MODE_FKEYS

static unsigned int appletb_tb_def_fn_mode = APPLETB_FN_MODE_NORM;
module_param(appletb_tb_def_fn_mode, uint, 0644);
MODULE_PARM_DESC(appletb_tb_def_fn_mode, "Default Function key mode");

static unsigned int appletb_tb_idle_timeout = 60;
module_param(appletb_tb_idle_timeout, uint, 0644);
MODULE_PARM_DESC(appletb_tb_idle_timeout, "Idle timeout in seconds");

static unsigned int appletb_tb_dim_timeout = 5;
module_param(appletb_tb_dim_timeout, uint, 0644);
MODULE_PARM_DESC(appletb_tb_dim_timeout, "Dim timeout in seconds");

static const unsigned int appletb_fn_remap[] = {
	KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8,
	KEY_F9, KEY_F10, KEY_F11, KEY_F12, KEY_ESC,
};

static const unsigned int appletb_fn_to_special[] = {
	KEY_ESC,	KEY_KBDILLUMDOWN, KEY_KBDILLUMUP, KEY_MUTE,
	KEY_VOLUMEDOWN, KEY_VOLUMEUP, KEY_PREVIOUSSONG, KEY_PLAYPAUSE,
	KEY_NEXTSONG, KEY_POWER, KEY_EJECTCD, KEY_MUTE, KEY_ESC,
};

static struct hid_driver appletb_hid_driver;

static const struct input_device_id appletb_input_devices[] = {
	{
		.flags = INPUT_DEVICE_ID_MATCH_BUS |
			INPUT_DEVICE_ID_MATCH_KEYBIT,
		.bustype = BUS_SPI,
		.keybit = { [BIT_WORD(KEY_FN)] = BIT_MASK(KEY_FN) },
		.driver_info = APPLETB_DEVID_KEYBOARD,
	},
	{
		.flags = INPUT_DEVICE_ID_MATCH_BUS |
			INPUT_DEVICE_ID_MATCH_KEYBIT,
		.bustype = BUS_SPI,
		.keybit = { [BIT_WORD(BTN_TOUCH)] = BIT_MASK(BTN_TOUCH) },
		.driver_info = APPLETB_DEVID_TOUCHPAD,
	},
	{ },
};

struct appletb_device {
	bool			active;
	struct device		*log_dev;

	struct appletb_report_info {
		struct hid_device	*hdev;
		struct usb_interface	*usb_iface;
		unsigned int		usb_epnum;
		unsigned int		report_id;
		unsigned int		report_type;
		bool			suspended;
	}			mode_info, disp_info;

	struct input_handler	inp_handler;
	struct input_handle	kbd_handle;

	unsigned int		fn_mode;
	unsigned int		idle_timeout;
	unsigned int		dim_timeout;

	spinlock_t		tb_lock;
	unsigned int		tb_mode;
	bool			tb_mode_valid;
	unsigned int		tb_dim_state;
	ktime_t			tb_last_activity;
	struct delayed_work	tb_work;
};

static ssize_t idle_timeout_show(struct device *dev,
				 struct device_attribute *attr,
				 char *buf)
{
	struct appletb_device *tb_dev = dev_get_drvdata(dev);
	return snprintf(buf, PAGE_SIZE, "%u\n", tb_dev->idle_timeout);
}

static ssize_t idle_timeout_store(struct device *dev,
				  struct device_attribute *attr,
				  const char *buf, size_t size)
{
	struct appletb_device *tb_dev = dev_get_drvdata(dev);
	unsigned int idle_timeout;

	if (sscanf(buf, "%u", &idle_timeout) != 1)
		return -EINVAL;

	tb_dev->idle_timeout = idle_timeout;
	return size;
}

static DEVICE_ATTR_RW(idle_timeout);

static ssize_t dim_timeout_show(struct device *dev,
				struct device_attribute *attr,
				char *buf)
{
	struct appletb_device *tb_dev = dev_get_drvdata(dev);
	return snprintf(buf, PAGE_SIZE, "%u\n", tb_dev->dim_timeout);
}

static ssize_t dim_timeout_store(struct device *dev,
				 struct device_attribute *attr,
				 const char *buf, size_t size)
{
	struct appletb_device *tb_dev = dev_get_drvdata(dev);
	unsigned int dim_timeout;

	if (sscanf(buf, "%u", &dim_timeout) != 1)
		return -EINVAL;

	tb_dev->dim_timeout = dim_timeout;
	return size;
}

static DEVICE_ATTR_RW(dim_timeout);

static ssize_t fnmode_show(struct device *dev, struct device_attribute *attr,
			   char *buf)
{
	struct appletb_device *tb_dev = dev_get_drvdata(dev);
	return snprintf(buf, PAGE_SIZE, "%u\n", tb_dev->fn_mode);
}

static ssize_t fnmode_store(struct device *dev, struct device_attribute *attr,
			    const char *buf, size_t size)
{
	struct appletb_device *tb_dev = dev_get_drvdata(dev);
	unsigned int fn_mode;

	if (sscanf(buf, "%u", &fn_mode) != 1 ||
	    fn_mode > APPLETB_FN_MODE_MAX)
		return -EINVAL;

	tb_dev->fn_mode = fn_mode;
	return size;
}

static DEVICE_ATTR_RW(fnmode);

static struct attribute *appletb_attrs[] = {
	&dev_attr_idle_timeout.attr,
	&dev_attr_dim_timeout.attr,
	&dev_attr_fnmode.attr,
	NULL,
};

static const struct attribute_group appletb_attr_group = {
	.attrs = appletb_attrs,
};

static int appletb_probe(struct hid_device *hdev,
			 const struct hid_device_id *id)
{
	struct appletb_device *tb_dev =
		appleib_get_drvdata(hid_get_drvdata(hdev), &appletb_hid_driver);

	if (!tb_dev) {
		hid_err(hdev, "Unable to get drvdata\n");
		return -ENODEV;
	}

	if (tb_dev->active)
		return 0;

	tb_dev->active = true;

	return 0;
}

static void appletb_remove(struct hid_device *hdev)
{
	struct appletb_device *tb_dev =
		appleib_get_drvdata(hid_get_drvdata(hdev), &appletb_hid_driver);

	if (!tb_dev)
		return;

	tb_dev->active = false;
}

#ifdef CONFIG_PM
static int appletb_suspend(struct hid_device *hdev, pm_message_t message)
{
	struct appletb_device *tb_dev =
		appleib_get_drvdata(hid_get_drvdata(hdev), &appletb_hid_driver);

	if (!tb_dev)
		return 0;

	cancel_delayed_work_sync(&tb_dev->tb_work);

	return 0;
}

static int appletb_reset_resume(struct hid_device *hdev)
{
	struct appletb_device *tb_dev =
		appleib_get_drvdata(hid_get_drvdata(hdev), &appletb_hid_driver);

	if (!tb_dev)
		return 0;

	schedule_delayed_work(&tb_dev->tb_work, 0);

	return 0;
}
#endif

static const struct hid_device_id appletb_input_devices[] = {
	{
		.flags = INPUT_DEVICE_ID_MATCH_BUS |
			INPUT_DEVICE_ID_MATCH_KEYBIT,
		.bustype = BUS_SPI,
		.keybit = { [BIT_WORD(KEY_FN)] = BIT_MASK(KEY_FN) },
		.driver_info = APPLETB_DEVID_KEYBOARD,
	},
	{
		.flags = INPUT_DEVICE_ID_MATCH_BUS |
			INPUT_DEVICE_ID_MATCH_KEYBIT,
		.bustype = BUS_SPI,
		.keybit = { [BIT_WORD(BTN_TOUCH)] = BIT_MASK(BTN_TOUCH) },
		.driver_info = APPLETB_DEVID_TOUCHPAD,
	},
	{ },
};

static struct hid_driver appletb_hid_driver = {
	.name = "apple-ib-touchbar",
	.probe = appletb_probe,
	.remove = appletb_remove,
#ifdef CONFIG_PM
	.suspend = appletb_suspend,
	.reset_resume = appletb_reset_resume,
#endif
};

static struct appletb_device *appletb_alloc_device(struct device *log_dev)
{
	struct appletb_device *tb_dev;

	tb_dev = kzalloc(sizeof(*tb_dev), GFP_KERNEL);
	if (!tb_dev)
		return NULL;

	spin_lock_init(&tb_dev->tb_lock);
	INIT_DELAYED_WORK(&tb_dev->tb_work, NULL);
	tb_dev->log_dev = log_dev;

	return tb_dev;
}

static void appletb_free_device(struct appletb_device *tb_dev)
{
	cancel_delayed_work_sync(&tb_dev->tb_work);
	kfree(tb_dev);
}

static int appletb_platform_probe(struct platform_device *pdev)
{
	struct appleib_device_data *ddata = pdev->dev.platform_data;
	struct appleib_device *ib_dev = ddata->ib_dev;
	struct appletb_device *tb_dev;
	int rc;

	tb_dev = appletb_alloc_device(ddata->log_dev);
	if (!tb_dev)
		return -ENOMEM;

	rc = appleib_register_hid_driver(ib_dev, &appletb_hid_driver, tb_dev);
	if (rc)
		goto error;

	platform_set_drvdata(pdev, tb_dev);

	sysfs_create_group(&pdev->dev.kobj, &appletb_attr_group);

	return 0;

error:
	appletb_free_device(tb_dev);
	return rc;
}

static int appletb_platform_remove(struct platform_device *pdev)
{
	struct appleib_device_data *ddata = pdev->dev.platform_data;
	struct appleib_device *ib_dev = ddata->ib_dev;
	struct appletb_device *tb_dev = platform_get_drvdata(pdev);
	int rc;

	sysfs_remove_group(&pdev->dev.kobj, &appletb_attr_group);

	rc = appleib_unregister_hid_driver(ib_dev, &appletb_hid_driver);
	if (rc)
		goto error;

	appletb_free_device(tb_dev);

	return 0;

error:
	return rc;
}

static const struct platform_device_id appletb_platform_ids[] = {
	{ .name = "apple-ib-tb" },
	{ }
};
MODULE_DEVICE_TABLE(platform, appletb_platform_ids);

static struct platform_driver appletb_platform_driver = {
	.id_table = appletb_platform_ids,
	.driver = {
		.name	= "apple-ib-tb",
	},
	.probe = appletb_platform_probe,
	.remove = appletb_platform_remove,
};

module_platform_driver(appletb_platform_driver);

MODULE_AUTHOR("Ronald Tschalär");
MODULE_DESCRIPTION("MacBookPro Touch Bar driver");
MODULE_LICENSE("GPL v2");
