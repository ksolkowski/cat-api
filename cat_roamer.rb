require 'base64'
require 'open-uri'
require 'nokogiri'
module CatRoamer
  URL_KEY          = "cats:urls"    # redis list of urls
  STORED_IMAGE_KEY = "cats:images"  # redis hash {sha8_key => stored_image}
  VIEWED_CAT_KEY   = "cats:views"   # redis hash {sha8_key => view_count}

  def fetch_or_download_cat_urls
    url = $redis.srandmember(URL_KEY) # cats exist

    if url.nil?
      page = (0..2010).to_a.sample
      html = Nokogiri::HTML(open("http://d.hatena.ne.jp/fubirai/?of=#{page}"))
      cat_urls = html.css("img.hatena-fotolife").to_a.map{|child| child.attributes["src"].value }
      url = cat_urls.sample
    end

    save_or_fetch_image_in_redis(url)
  end

  def get_cat_stats
    @images_saved = fetch_all_stored_images.count
    @urls_saved = $redis.smembers(URL_KEY).count
    @views = fetch_all_views
  end

  def fetch_all_views
    $redis.hgetall VIEWED_CAT_KEY
  end

  def increment_view_count(base_key)
    $redis.hincrby VIEWED_CAT_KEY, base_key, 1
  end

  def store_cat_urls(urls)
    $redis.sadd URL_KEY, urls
  end

  def store_cat_url(url)
    $redis.sadd URL_KEY, url
  end

  def remove_cat_url(url)
    $redis.srem URL_KEY, url
  end

  def remove_url_and_image(url)
    remove_cat_url(url)
    key = base_redis_key(url)
    $redis.hdel STORED_IMAGE_KEY, key
    $redis.hdel VIEWED_CAT_KEY, key
  end

  def fetch_all_stored_images
    $redis.hkeys(STORED_IMAGE_KEY)
  end

  def clear_cached_cats
    $redis.del URL_KEY
    count = $redis.hkeys(STORED_IMAGE_KEY).count
    $redis.del STORED_IMAGE_KEY
    $redis.del VIEWED_CAT_KEY

    count
  end

  def already_saved?(key)
    $redis.hexists(STORED_IMAGE_KEY, key)
  end

  def fetch_saved_image(key)
    increment_view_count(key)
    $redis.hget(STORED_IMAGE_KEY, key)
  end

  def save_image(url, key)
    raw_img = Base64.encode64(open(url).read)
    store_cat_url(url)
    $redis.hset STORED_IMAGE_KEY, key, raw_img
    raw_img
  end

  def fetch_and_decode(key)
    raw_img = fetch_saved_image(key)
    decode_image(raw_img)
  end

  def decode_image(raw_img)
    Base64.decode64 raw_img
  end

  def key_to_path(key)
    key + ".jpg"
  end

  def save_or_fetch_image_in_redis(url)
    key = base_redis_key(url)

    if already_saved?(key)
      raw_img = fetch_saved_image(key)
    else # store it in redis
      store_cat_url(url)
      raw_img = save_image(url, key)
    end

    [decode_image(raw_img), key_to_path(key)]
  end

  private

  def base_redis_key(url)
    Digest::SHA1.hexdigest(url)
  end

  def base_key(key)
    key.split(":").last
  end

end