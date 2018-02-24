# ./app.rb
require "roda"
require 'open-uri'
require 'nokogiri'
require "redis"
require "json"
require "base64"

uri = URI.parse(ENV["REDIS_URL"]||"redis://localhost:6379")
$redis = Redis.new(host: uri.host, port: uri.port, password: uri.password)
ENV["SITE_URL"] ||= "localhost:3000"

class CatApi < Roda
  EXPIRES_IN = ((60 * 5) * 100) # 5 min in ms
  EXPIRE_KEY = "cats:expire:"
  STORE_KEY  = "cats:urls:"
  STORED_IMAGE_KEY = "cats:images:"
  NO_CAT_LIST = ['austinkahly', 'murph', 'nichelle']

  plugin :json

  def fetch_or_download_cat_urls
    if cat_urls = $redis.get(STORE_KEY) # cats exist
      clear_cached_cats if urls_expired?
      url = JSON.parse(cat_urls).sample
    else
      page = (0..2010).to_a.sample
      html = Nokogiri::HTML(open("http://d.hatena.ne.jp/fubirai/?of=#{page}"))
      cat_urls = html.css("img.hatena-fotolife").to_a.map{|child| child.attributes["src"].value }
      store_cat_urls(cat_urls)
      url = cat_urls.sample
    end

    decoded_image, path = save_image_to_redis(url)
  end

  def urls_expired?
    cats_expires = $redis.get EXPIRE_KEY
    return false if cats_expires.nil?
    cats_expires.to_i < Time.now.to_i
  end

  def store_cat_urls(urls)
    $redis.set STORE_KEY, urls.to_json
    $redis.set EXPIRE_KEY, (Time.now.to_i + EXPIRES_IN)
  end

  def clear_cached_cats
    $redis.del STORE_KEY
    $redis.del EXPIRE_KEY
  end

  # some helper functions for images
  def url_to_redis_key(url)
    # pop off the tail png
    key = url.gsub(/[^0-9A-Za-z\-]/, '_').gsub("jpg", "")# + ".jpg"
    STORED_IMAGE_KEY + key
  end

  def already_saved?(key)
    $redis.exists(key)
  end

  def fetch_saved_image(key)
    $redis.get(key)
  end

  def save_image(url, key)
    raw_img = Base64.encode64(open(url).read)
    $redis.set key, raw_img
    raw_img
  end

  def fetch_and_decode(key)
    raw_img = fetch_saved_image(key)
    decode_image(raw_img)
  end

  def decode_image(raw_img)
    Base64.decode64 raw_img
  end

  def key_to_url(key)
    key.gsub(STORED_IMAGE_KEY, '') + ".jpg"
  end

  def save_image_to_redis(url)
    key = url_to_redis_key(url)

    if already_saved?(key)
      raw_img = fetch_saved_image(key)
    else # store it in redis
      raw_img = save_image(url, key)
    end

    [decode_image(raw_img), key_to_url(key)]
  end

  route do |r|

    r.root do
      "hello"
    end

    r.on "cats" do
      if r.is_get?
        response['Content-Type'] = "text/plain"
        decoded_image, fake_path = fetch_or_download_cat_urls
        decoded_image
      else
        response['Content-Type'] = 'application/json'
        if NO_CAT_LIST.include?(r.params["user_name"]) and r.params["text"] != "cats are great"
          {
            response_type: "in_channel",
            text: "Come back when you have a cat"
          }
        else
          decoded_image, fake_path = fetch_or_download_cat_urls

          real_url = File.join ENV["SITE_URL"], fake_path
          clear_cached_cats if r.params["text"] != "clear"
          {
            response_type: "in_channel",
            attachments: [
              {
                fallback: "<3 Cats <3",
                color: "#36a64f",
                title: "Check out this cat",
                title_link: "Cats",
                fields: [],
                image_url: real_url,
                thumb_url: real_url,
                ts: Time.now.to_i
              }
            ]
          }.to_json
        end
      end
    end

    r.on "clear_cats" do
      clear_cached_cats
      "cleared"
    end


    r.get do
      cleaned = request.remaining_path[1..-1].gsub(".jpg", "")
      key = url_to_redis_key(cleaned)
      if already_saved?(key)
        response['Content-Type'] = "text/plain"
        fetch_and_decode(key)
      end
    end

  end
end