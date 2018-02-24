require 'base64'
require 'open-uri'
require 'nokogiri'
module CatRoamer
  EXPIRES_IN = (60 * 10) # 10 min
  EXPIRE_KEY = "cats:expire:"
  STORE_KEY  = "cats:urls:"
  STORED_IMAGE_KEY = "cats:images:"

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
    stored_images = $redis.keys(STORED_IMAGE_KEY + "*")

    stored_images.each do |key|
      $redis.del key
    end

    stored_images.count
  end

  def url_to_redis_key(url)
    key = Digest::SHA1.hexdigest(url)
    STORED_IMAGE_KEY + key
  end

  def already_saved?(key)
    $redis.exists(key)
  end

  def fetch_saved_image(key)
    $redis.get(key)
  end

  def save_image(url, key)
    raw_img = Base64.encode64 open(url).read
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

  def cleaned_path_to_key(cleaned)
    STORED_IMAGE_KEY + cleaned
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

end