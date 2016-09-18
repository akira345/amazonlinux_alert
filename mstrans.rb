require 'rexml/document'
require 'json'
require 'yaml'
require 'net/http'
require 'uri'

# http://hamasyou.com/blog/2014/02/14/microsoft-translator-api/ より

class MS_Translator

  def initialize
    @authorize_url   = 'https://datamarket.accesscontrol.windows.net/v2/OAuth2-13/'
    @translation_url = 'http://api.microsofttranslator.com/V2/Http.svc/Translate'
    @scope           = 'http://api.microsofttranslator.com'

    config=YAML.load_file("config.yml")
    @client_id       = config['client_id']
    @client_secret   = config['client_secret']
  end

  def get_access_token
    access_token = nil
    post_data = {
      'grant_type' => 'client_credentials',
      'client_id' => @client_id,
      'client_secret' => @client_secret,
      'scope' => @scope
    }
    res = Net::HTTP.post_form(URI.parse(@authorize_url),post_data)
    json = JSON.parse(res.body)
    access_token = json['access_token']

    access_token
  end


  def translate_text(text)
    access_token = get_access_token

    url = URI.parse("#{@translation_url}?from=en&to=ja&text=#{URI.escape(text)}")
    req = Net::HTTP::Get.new(url.request_uri)
    req['Authorization'] = "Bearer #{access_token}"

    res = Net::HTTP.start(url.host,url.port) do |http|
      http.request(req)
    end
    xml = REXML::Document.new(res.body)
    xml.root.text
  end
end

