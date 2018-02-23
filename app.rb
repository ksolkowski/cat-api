# ./app.rb
require "roda"
require 'open-uri'
require 'nokogiri'

require "redis"
require "json"

uri = URI.parse(ENV["REDIS_URL"]||"redis://localhost:6379")
$redis = Redis.new(host: uri.host, port: uri.port, password: uri.password)

class CatApi < Roda
  EXPIRES_IN = ((60 * 5) * 100) # 5 min in ms
  EXPIRE_KEY = "cats:expire:"
  STORE_KEY  = "cats:urls:"
  NO_CAT_LIST = ['austinkahly', 'murph', 'nichelle']

  plugin :json

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

  # some helper functions for images
  def url_to_filename(url)
    # pop off the tail png
    clean_url = url.gsub(".png", "")
    clean_url = clean_url.gsub(".jpg", "")
    clean_url.gsub!(/[^0-9A-Za-z\-]/, '_')

    # store these in the tmp folder!
    # always png!
    Rails.root.join('tmp', "#{clean_url}.png")
  end

  def open_or_save_image(url)
    path = url_to_filename(url)
    if image_saved_on_file?(path) #and !@single # single ones don't care about
      @open_images[path]
    else
      @downloaded_images_count ||= 0
      @downloaded_images_count += 1
      save_to_tempfile(url, path)
    end
    path
  end

  def image_saved_on_file?(path)
    path = Rails.root.join('tmp', path)
    @open_images ||= {}
    @open_images[path] = path if File.exists?(path) # add it to the open images hash
    File.size?(path)
  end

  def save_to_tempfile(url, path)
    @open_images ||= {}
    @open_images[path] = path
    if !File.size?(path)
      File.open(path, 'wb+') do |file|
        file.binmode

        retries = 0
        begin
          downloaded_file = open(url).read
          file.write downloaded_file
        rescue => e
          if retries < 5
            retries += 1
            Rails.logger.info "retrying to download #{url} with #{e.message} failed #{retries} times so far"
            retry
          else
            raise
          end
        end
      end
      path
    else
      path
    end
  end

  route do |r|

    r.root do
      "hello"
    end

    r.on "cats" do
      if r.is_get?
        "<img src=\"#{fetch_or_download_cat_urls}\"></img>"
      else
        response['Content-Type'] = 'application/json'
        if NO_CAT_LIST.include?(r.params["user_name"]) and r.params["text"] != "cats are great"
          {
            "response_type": "in_channel",
            "text": "Come back when you have a cat"
          }
        else
          image = fetch_or_download_cat_urls
          clear_cached_cats if r.params["text"] != "clear"
          {
            "response_type": "in_channel",
            "attachments": [
              {
                  "fallback": "<3 Cats <3",
                  "color": "#36a64f",
                  "title": "Check out this cat",
                  "title_link": "Cats",
                  "fields": [],
                  "image_url": image,
                  "thumb_url": image,
                  "ts": Time.now.to_i
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
  end
end