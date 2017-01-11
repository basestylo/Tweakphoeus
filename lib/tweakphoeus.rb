require "tweakphoeus/version"
require "typhoeus"

module Tweakphoeus
  class Client
    attr_accessor :cookie_jar
    attr_accessor :base_headers

    def initialize()
      @cookie_jar = {}
      @referer = [""]
      @base_headers = {
        "User-Agent" => "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:42.0) Gecko/20100101 Firefox/42.0",
        "Accept-Language" => "es-ES,es;q=0.8,en-US;q=0.5,en;q=0.3",
        "Accept-Encoding" => "",
        "Connection" => "keep-alive"
      }
    end

    def get(url, body: nil, params: nil, headers: nil, redirect: true)
      set_referer_from_headers(headers)
      http_request(url, body: body, params: params, headers: headers, redirect: redirect, method: :get)
    end

    def delete(url, body: nil, headers: nil, redirect: true)
      set_referer_from_headers(headers)
      http_request(url, body: body, headers: headers, redirect: redirect, method: :delete)
    end

    def post(url, body: nil, params: nil, headers: nil, redirect: false)
      set_referer_from_headers(headers)
      http_request(url, body: body, params: nil, headers: headers, redirect: redirect, method: :post)
    end

    def get_hide_inputs response
      #TODO
    end

    def add_cookies host, key, value
      domain = get_domain(host)
      @cookie_jar[domain] ||= {}
      @cookie_jar[domain][key] = value
    end

    def get_domain domain
      domain.match(/([a-zA-Z0-9]+:\/\/|)([^\/]+)/)[2].gsub(/^\./,'')
    end

    def push_referer url = ""
      @referer << url
      url
    end

    def pop_referer
      @referer.pop
    end

    def get_referer
      @referer.last
    end

    def cookie_string(url, headers={})
      domain = get_domain(url)
      headers ||= {}
      cookies = parse_cookie(headers["Cookie"])

      while domain.present?
        if @cookie_jar[domain]
          @cookie_jar[domain].each do |key, value|
            cookies[key] ||= value
          end
        end
        domain = domain.gsub(/^([^\.]+\.?)/, '')
      end

      cookies.map{ |key, value| "#{key}=#{value}" }.join('; ')
    end

    private

    def http_request(url, body: nil, params: nil, headers: nil, redirect: false, method: method)
      request_headers = merge_default_headers(headers)
      request_headers["Cookie"] = cookie_string(url, headers)
      request_headers["Referer"] = get_referer
      response = Typhoeus.send(method, url, body: body, params: params, headers: request_headers)
      obtain_cookies(response)
      set_referer(url) if method != :post
      if redirect && has_redirect?(response)
        if response.code != 307
          method = :get
          body = nil
        end
        response = http_request(redirect_url(response),
                                body: body,
                                headers: headers,
                                redirect: redirect,
                                method: method)
      end
      response
    end

    def merge_default_headers headers
      headers ? @base_headers.merge(headers) : @base_headers
    end

    def obtain_cookies response
      set_cookies_field = response.headers["Set-Cookie"]
      return if set_cookies_field.nil?
      if set_cookies_field.is_a?(String)
        set_cookies_field = [set_cookies_field]
      end

      set_cookies_field.each do |cookie|
        key, value = cookie.match(/^([^=]+)=(.+)/).to_a[1..-1]
        domain = cookie.match(/Domain=([^;]+)/)

        if domain.nil?
          domain = get_domain(response.request.url)
        else
          domain = domain[1].gsub(/^\./,'')
        end

        value = value.split(';').first
        if value != "\"\""
          @cookie_jar[domain] ||= {}
          @cookie_jar[domain][key] = value
        else
          @cookie_jar[domain] ||= {}
          @cookie_jar[domain].delete(key)
        end
      end
    end

    def parse_cookie(string)
      cookies = {}

      if string.is_a?(String)
        string.split(';').each do |part|
          key, value = part.split('=')
          key.strip!
          cookies[key.strip] = value if value && !["Domain","Path","domain","path"].include?(key)
        end
      end

      cookies
    end

    def has_redirect? response
      !redirect_url(response).nil?
    end

    def redirect_url response
      response.headers["Location"]
    end

    def purge_bad_cookies cookies
      cookies.reject{|e| e.first.last=="\"\""}
    end

    def set_referer_from_headers headers
      if headers && headers["Referer"].is_a?(String)
        @referer.last.replace headers["Referer"]
      end
    end

    def set_referer url
      @referer.last.replace url
    end

  end
end
