class FortyTwo::Api
  class DataStruct < OpenStruct
    def as_json(*args)
      super.as_json['table']
    end
  end

  class Response
    attr_reader :app, :status, :body, :error

    def initialize(status:, body: nil, app: {}, error: {})
      @app = App.new(app)
      @status = status
      @error = Error.new(error)
      @body = body
    end

    def success?
      status == :success
    end

    class App
      attr_reader :id, :name

      def initialize(id: nil, name: nil)
        @id = id
        @name = name
      end
    end

    class Error
      attr_reader :code, :message

      def initialize(code: nil, message: nil)
        @code = code
        @message = message
      end
    end
  end

  def authorize(code:, redirect_uri:)
    response = Faraday.post('https://api.intra.42.fr/oauth/token', {
      code: code,
      client_id: @uid,
      client_secret: @secret,
      redirect_uri: redirect_uri,
      grant_type: :authorization_code
    })

    status = response.status.in?(200..399) ? :success : :failure
    data = JSON.parse(response.body, object_class: DataStruct)
    error = { code: response.status, message: data.error} if response.status > 399

    Response.new(status: status, error: error || {}, body: data)
  end

  def self.instance
    $forty_two_instance ||= self.new(uid: Secrets.get(:forty_two, :client_uid), secret: Secrets.get(:forty_two, :client_secret))
  end

  def initialize(uid: nil, secret: nil, access_token: nil, refresh_token: nil)
    @uid = uid
    @secret = secret
    @access_token = access_token
    @refresh_token = refresh_token
  end

  def get(path, params = {})
    per_page = params.delete(:per_page) || 100
    response, next_page = request(:get, path, params: params.merge(per_page: per_page))

    return build_response(response) unless response.status.in?(200..299)

    if block_given?
      continue = yield JSON.parse(response.body, object_class: DataStruct)
      return build_response(response, status: next_page ? :partial : :success) unless continue
    else
      data = JSON.parse(response.body, object_class: DataStruct)
    end

    while next_page
      response, next_page = request(:get, path, params: params.merge(page: next_page, per_page: per_page))
      return build_response(response, status: :partial, body: data) unless response.status.in?(200..299)

      if block_given?
        continue = yield JSON.parse(response.body, object_class: DataStruct)
        return build_response(response, status: next_page ? :partial : :success) unless continue
      else
        data += JSON.parse(response.body, object_class: DataStruct)
      end
    end if params[:page].nil?

    build_response(response, body: data)
  end

private

  def build_response(response, status: nil, body: nil)
    status = response.status.in?(200..399) ? :success : :failure if status.nil?
    app = { id: response.headers['x-application-id'].to_i, name: response.headers['x-application-name'].to_s }
    error = { code: response.status, message: response.parsed['message'].to_s} if response.status > 399

    Response.new(status: status, app: app, error: error || {}, body: body)
  end

  def token(force_refresh: false)
    @token = if !@token || (!@token.refresh_token && (@token.expired? || force_refresh))
               oauth2_client = OAuth2::Client.new(@uid, @secret, site: 'https://api.intra.42.fr')

               (@access_token ?
                 OAuth2::AccessToken.from_hash(oauth2_client, access_token: @access_token, refresh_token: @refresh_token)
               :
                 oauth2_client.client_credentials.get_token
               )
             elsif @token.refresh_token && (@token.expired? || force_refresh)
               @token.refresh!
             else
               @token
             end
  end

  def request(method, path, opts = {})
    opts[:max_retries] ||= 2
    opts[:retry_count] ||= 0
    opts[:retry_count] += 1

    uri = URI(path.gsub(' ', '%20'))
    path = uri.path
    query = Rack::Utils.parse_nested_query(uri.query).merge(opts.reject { |k, v| k.in?(%i(max_retries retry_count)) })

    begin
      response = token.send(method, path, query)
      headers = response.headers
      # limit_remaining = (headers['x-ratelimit-remaining'] || 1).to_i
      # limit_max = headers['x-ratelimit-limit'].to_i

      x_page = (headers['x-page'] || 1).to_i
      x_per_page = (headers['x-per-page'] || 1).to_f
      x_total = ((headers['x-total'] || 1).to_f / x_per_page).ceil

      raise response.error if response.error

      [response, x_page < x_total ? x_page + 1 : nil]
    rescue OAuth2::Error => e
      body = JSON.parse(e.message.split("\n")[1])

      if opts[:retry_count] > opts[:max_retries]
        token(force_refresh: true) if body['message'] == 'The access token expired'
        sleep 1 if e.message.match(%r(Spam Rate Limit Exceeded))
        retry
      end

      e.response
    end
  end
end
