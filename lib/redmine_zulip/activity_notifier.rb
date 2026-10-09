module RedmineZulip
  # Mirrors the notification emails Redmine sends for non-issue events
  # (news, news comments, documents, files, forum messages, wiki pages) into
  # Zulip. Issue notifications keep their own path (IssuePatch), which also
  # sends the assignee DM.
  class ActivityNotifier
    def self.publish(event, record, author: nil)
      new(event, record, author).publish
    end

    def initialize(event, record, author = nil)
      @event = event
      @record = record
      @author = author
      @locale = Setting.default_language
    end

    def publish
      settings = RedmineZulip::Settings.new(project)
      return false unless settings.enabled? &&
                          settings.stream.present? &&
                          settings.issue_updates_subject.present?

      RedmineZulip::Api.new(
        url: settings.zulip_url,
        email: settings.zulip_email,
        key: settings.zulip_api_key
      ).messages.send(
        type: "stream",
        to: settings.stream,
        subject: settings.issue_updates_subject,
        content: content
      )
    end

    def content
      send(@event)
    end

    private

    def project
      @record.is_a?(Array) ? @record.first.container.project : @record.project
    end

    def author_name
      actor = @author
      actor ||= @record.author if @record.respond_to?(:author)
      actor ||= @record.first.try(:author) if @record.is_a?(Array)
      (actor || User.current).try(:name).to_s
    end

    def base_url
      "#{Setting[:protocol]}://#{Setting[:host_name]}"
    end

    def t(key, **options)
      I18n.t(key, locale: @locale, **options)
    end

    def quoted(text)
      return "" if text.blank?

      "\n\n~~~quote\n#{text}\n~~~\n"
    end

    def attachment_lines(attachments)
      list = Array(attachments).compact
      return "" if list.empty?

      "\n\n* **#{I18n.t(:label_attachment_plural, locale: @locale)}**\n" +
        list.map { |a| "* #{a.filename} (#{ActiveSupport::NumberHelper.number_to_human_size(a.filesize)})" }
            .join("\n") + "\n"
    end

    def news_added
      news = @record
      url = "#{base_url}/news/#{news.id}"
      t("zulip_notify_news_added", user: author_name, title: news.title, url: url) +
        quoted(news.description) +
        attachment_lines(news.attachments)
    end

    def news_comment_added
      news = @record.commented
      url = "#{base_url}/news/#{news.id}"
      t("zulip_notify_news_comment_added", user: author_name, title: news.title, url: url) +
        quoted(@record.content)
    end

    def document_added
      document = @record
      url = "#{base_url}/documents/#{document.id}"
      t("zulip_notify_document_added", user: author_name, title: document.title,
        category: document.category.try(:name), url: url) +
        quoted(document.description)
    end

    def attachments_added
      attachments = Array(@record)
      container = attachments.first.container
      url, label =
        case container
        when Document
          ["#{base_url}/documents/#{container.id}",
           "#{I18n.t(:label_document, locale: @locale)}: #{container.title}"]
        when Version
          ["#{base_url}/projects/#{container.project.identifier}/files",
           "#{I18n.t(:label_version, locale: @locale)}: #{container.name}"]
        else
          ["#{base_url}/projects/#{container.project.identifier}/files",
           "#{I18n.t(:label_project, locale: @locale)}: #{container.project}"]
        end

      t("zulip_notify_file_added", user: author_name, container: label, url: url) +
        attachment_lines(attachments)
    end

    def message_posted
      message = @record
      root = message.root
      url = "#{base_url}/boards/#{message.board_id}/topics/#{root.id}"
      t("zulip_notify_message_posted", user: author_name, subject: message.subject,
        board: message.board.name, url: url) +
        quoted(message.content) +
        attachment_lines(message.attachments)
    end

    def wiki_content_added
      wiki = @record
      url = wiki_url(wiki)
      t("zulip_notify_wiki_added", user: author_name, title: wiki.page.pretty_title, url: url) +
        quoted([wiki.comments, wiki.text].reject(&:blank?).join("\n\n"))
    end

    def wiki_content_updated
      wiki = @record
      url = wiki_url(wiki)
      t("zulip_notify_wiki_updated", user: author_name, title: wiki.page.pretty_title, url: url) +
        quoted([wiki.comments, wiki.text].reject(&:blank?).join("\n\n")) +
        "\n* #{t('zulip_notify_wiki_diff', url: "#{url}/diff/#{wiki.version}")}\n"
    end

    def wiki_url(wiki)
      "#{base_url}/projects/#{wiki.project.identifier}/wiki/#{wiki.page.title}"
    end
  end
end
