require 'net/http'

module OpenID
  # Our HTTPResponse class extends Net::HTTPResponse with an additional
  # method, final_url.
  class HTTPResponse
    attr_accessor :final_url

    attr_accessor :_response

    def self._from_net_response(response, final_url, headers=nil)
      me = self.new
      me._response = response
      me.initialize_http_header headers
      me.final_url = final_url
      return me
    end

    def self._from_raw_data(status, body="", headers={}, final_url=nil)
      resp = Net::HTTPResponse.new('1.1', status, 'NONE')
      me = self._from_net_response(resp, final_url, headers)
      me.body = body
      return me
    end

    def method_missing(method, *args)
      @_response.send(method, *args)
    end

    def body=(s)
      @_response.instance_variable_set('@body', s)
      # XXX Hack to work around ruby's HTTP library behavior.  @body
      # is only returned if it has been read from the response
      # object's socket, but since we're not using a socket in this
      # case, we need to set the @read flag to true to avoid a bug in
      # Net::HTTPResponse.stream_check when @socket is nil.
      @_response.instance_variable_set('@read', true)
    end
  end

  class HTTPRedirectLimitReached < StandardError
  end

  @@default_fetcher = nil

  def OpenID.fetch(url, body=nil, headers=nil,
                   redirect_limit=StandardFetcher::REDIRECT_LIMIT)
    fetcher = get_current_fetcher()
    return fetcher.fetch(url, body, headers, redirect_limit)
  end

  def OpenID.get_current_fetcher
    if @@default_fetcher.nil?
      @@default_fetcher = StandardFetcher.new
    end

    return @@default_fetcher
  end

  def OpenID.set_default_fetcher(fetcher)
    @@default_fetcher = fetcher
  end

  class StandardFetcher

    # FIXME: Use an OpenID::VERSION constant here.
    USER_AGENT = "ruby-openid/VERSION (#{PLATFORM})"

    REDIRECT_LIMIT = 5

    def fetch(url, body=nil, headers=nil, redirect_limit=REDIRECT_LIMIT)
      headers ||= {}
      headers['User-agent'] ||= USER_AGENT
      httpthing = Net::HTTP.new(url.host, url.port)
      if body.nil?
        response = httpthing.request_get(url.request_uri, headers)
      else
        headers["Content-type"] ||= "application/x-www-form-urlencoded"
        response = httpthing.request_post(url.request_uri, body, headers)
      end
      case response
      when Net::HTTPRedirection
        redirect_url = URI.parse(response["location"])
        if redirect_limit <= 0
          raise HTTPRedirectLimitReached.new(
            "Too many redirects, not fetching #{redirect_url}")
        end
        return fetch(redirect_url, body, headers, redirect_limit - 1)
      else
        return HTTPResponse._from_net_response(response, url)
      end
    end
  end
end
