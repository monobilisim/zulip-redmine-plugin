module RedmineZulip
  class Api
    TIMEOUT = 10

    attr_reader :url, :email, :key

    def initialize(url:, email:, key:)
      @url = "#{url}/api/v1"
      @key = key
      @email = email
    end

    def configured?
      url.present? && email.present? && key.present?
    end

    def messages
      RedmineZulip::Api::Messages.new(self)
    end

    private

    class Messages
      attr_reader :api

      def initialize(api)
        @api = api
      end

      def send(type:, to:, content:, subject: nil)
        form_data = {
          "type" => type,
          "to" => to,
          "content" => content
        }
        form_data["subject"] = subject if subject.present?
        uri = URI("#{api.url}/messages")
        req = Net::HTTP::Post.new(uri)
        req.basic_auth(api.email, api.key)
        req["User-Agent"] = "ZulipRedminePlugin/#{RedmineZulip::VERSION}"
        req.set_form_data(form_data)
        http = Net::HTTP.new(uri.hostname, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = TIMEOUT
        http.read_timeout = TIMEOUT
        res = http.start { |connection| connection.request(req) }
        unless res.code == "200"
          Rails.logger.warn("Zulip API #{res.code}: #{res.body}")
        end
        res.code == "200"
      rescue StandardError => e
        Rails.logger.warn("Zulip API error: #{e.class}: #{e.message}")
        false
      end
    end
  end
end
