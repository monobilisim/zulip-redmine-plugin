require File.expand_path('lib/redmine_zulip', __dir__)

Redmine::Plugin.register :redmine_zulip do
  name 'Zulip'
  author 'Zulip, Inc.'
  description 'Sends notifications to Zulip.'
  version RedmineZulip::VERSION
  url 'https://github.com/monbilisim/zulip-redmine-plugin'
  author_url 'https://www.zulip.org/'

  requires_redmine version_or_higher: '4.0.0'

  settings partial: "settings/redmine_zulip", default: {
    "zulip_url" => "",
    "zulip_email" => "",
    "zulip_api_key" => "",
    "zulip_stream_expression" => "${project_name}",
    "zulip_issue_updates_subject_expression" => "${project_identifier}",
    "zulip_version_updates_subject_expression" => ""
  }
end

