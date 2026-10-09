# Redmine Zulip Plugin

Get Zulip notifications for your Redmine issues!

## Compatibility

| Redmine Zulip Plugin version | Redmine version |
| ---------------------------- | --------------- |
| 1.x                          | 3.x             |
| 2.x                          | 3.x             |
| 3.x                          | 4.x,5.x,6.x     |

## Installing

0. Please navigate to your Redmine instance's root directory by running:

```sh
cd /path/to/redmine
```

1. Clone the **Redmine Zulip Plugin** into `plugins` directory

```sh
git clone https://github.com/monobilisim/zulip-redmine-plugin.git plugins/redmine_zulip
```

2. **Restart** your Redmine instance

3. Update the Redmine database by running:

```sh
rake redmine:plugins:migrate
```

## Configuring plugin settings

Log into your Redmine instance, click on **Administration** in the top-left
corner, then click on **Plugins**.

Find the **Redmine Zulip** plugin, and click **Configure**. You must now set the
following:

* Zulip URL (e.g `https://yourZulipDomain.zulipchat.com/`)
* Zulip Bot E-mail
* Zulip Bot API key
* Stream name __*__
* Issue updates subject __*__
* Version updates subject __*__

_* You may set dynamic values by using the following self-explanatory
variables:_

* ${issue_id}
* ${issue_subject}
* ${project_name}
* ${version_name}

#### Project settings

To override global settings project wise, go to your project's **Settings**
page, and select the **Zulip** tab.

## Notification types

The plugin mirrors Redmine's activity notification e-mails into Zulip, one
message per event, using the configured stream and subject:

| Event | Zulip |
| ----- | ----- |
| Issue created / updated (notes, changed fields) | stream message |
| Issue assigned / unassigned | private message to the assignee |
| News added / commented | stream message |
| Document added, file and document attachments | stream message |
| Forum message posted | stream message |
| Wiki page added / updated | stream message |

Events turned off in **Administration → Settings → Email notifications** are not
mirrored either. Message bodies are sent in full (notes, descriptions, wiki
text); a message longer than Zulip's limit is truncated with a trailing `…`.
