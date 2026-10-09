module RedmineZulip
  VERSION = "3.0.0"
end
Issue.send(:include, RedmineZulip::IssuePatch)
Project.send(:include, RedmineZulip::ProjectPatch)
Mailer.singleton_class.prepend(RedmineZulip::MailerPatch)
ProjectsController.send(:helper, RedmineZulip::ProjectSettingsTabs)