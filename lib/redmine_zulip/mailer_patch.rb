module RedmineZulip
  # Redmine sends every activity notification mail from a single
  # Mailer.deliver_* class method, each already gated by
  # Setting.notified_events. Wrapping those methods is what keeps Zulip in
  # step with the mails, including mail triggered from controllers
  # (file/document attachments) that no model callback would catch.
  module MailerPatch
    def deliver_news_added(news)
      RedmineZulip::ActivityNotifier.publish("news_added", news)
      super
    end

    def deliver_news_comment_added(comment)
      RedmineZulip::ActivityNotifier.publish("news_comment_added", comment)
      super
    end

    def deliver_document_added(document, author)
      RedmineZulip::ActivityNotifier.publish("document_added", document, author: author)
      super
    end

    def deliver_attachments_added(attachments)
      RedmineZulip::ActivityNotifier.publish("attachments_added", attachments)
      super
    end

    def deliver_message_posted(message)
      RedmineZulip::ActivityNotifier.publish("message_posted", message)
      super
    end

    def deliver_wiki_content_added(wiki_content)
      RedmineZulip::ActivityNotifier.publish("wiki_content_added", wiki_content)
      super
    end

    def deliver_wiki_content_updated(wiki_content)
      RedmineZulip::ActivityNotifier.publish("wiki_content_updated", wiki_content)
      super
    end
  end
end
