# ./app.rb
require "roda"
require 'open-uri'
require 'nokogiri'

require "redis"
require "json"

uri = URI.parse(ENV["REDIS_URL"]||"redis://localhost:6379")
puts "uri.host: #{ENV["REDIS_URL"]}"
$redis = Redis.new(host: uri.host, port: uri.port, password: uri.password)

class CatApi < Roda
  EXPIRES_IN = ((60 * 5) * 100) # 5 min in ms
  EXPIRE_KEY = "cats:expire:"
  STORE_KEY  = "cats:urls:"

  def fetch_or_download_cat_urls
    if cat_urls = $redis.get(STORE_KEY) # cats exist
      clear_cat_urls if urls_expired?
      JSON.parse(cat_urls).sample
    else
      page = (0..2010).to_a.sample
      html = Nokogiri::HTML(open("http://d.hatena.ne.jp/fubirai/?of=#{page}"))
      cat_urls = html.css("img.hatena-fotolife").to_a.map{|child| child.attributes["src"].value }
      store_cat_urls(cat_urls)
      cat_urls.sample
    end
  end

  def urls_expired?
    cats_set = $redis.get EXPIRE_KEY
    return false if cats_set.nil?
    cats_set.to_i < Time.now.to_i
  end

  def store_cat_urls(urls)
    $redis.set STORE_KEY, urls.to_json
    $redis.set EXPIRE_KEY, (Time.now.to_i + EXPIRES_IN)
  end

  def clear_cached_cats
    $redis.del STORE_KEY
    $redis.del EXPIRE_KEY
  end

  route do |r|

    r.root do
      "hello"
    end

    r.on "cats" do
      fetch_or_download_cat_urls
    end

    r.on "clear_cats" do
      clear_cached_cats
      "cleared"
    end
  end
end