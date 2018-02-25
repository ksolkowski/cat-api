require 'base64'
require 'open-uri'
require 'nokogiri'
module CatRoamer
  STORE_KEY        = "cats:urls:"
  STORED_IMAGE_KEY = "cats:images:"
  VIEWED_CAT_KEY   = "cats:views:"

  def fetch_or_download_cat_urls
    if cat_urls = $redis.get(STORE_KEY) # cats exist
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

  def get_cat_stats
    @images_saved = fetch_all_stored_images.count
  end

  def store_cat_urls(urls)
    $redis.set STORE_KEY, urls.to_json
  end

  def store_cat_url(url)
    urls = $redis.get STORE_KEY
    if urls
      urls = JSON.parse(urls)
    else
      urls = []
    end
    urls.push url if !urls.include?(url)
    $redis.set STORE_KEY, urls.to_json
  end

  def remove_cat_url(url)
    urls = $redis.get STORE_KEY
    if urls
      urls = JSON.parse(urls)
    else
      urls = []
    end
    urls.reject!{|x| x == url }
    $redis.set STORE_KEY, urls.to_json
  end

  def fetch_all_stored_images
    $redis.keys(STORED_IMAGE_KEY + "*")
  end

  def clear_cached_cats
    $redis.del STORE_KEY
    stored_images = fetch_all_stored_images

    $redis.keys(VIEWED_CAT_KEY + "*").each do |key|
      $redis.del key
    end

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
    raw_img = Base64.encode64(open(url).read)
    store_cat_url(url)
    $redis.set key, raw_img
    raw_img
  end

  def fetch_and_decode(key)
    raw_img = fetch_saved_image(key)
    #increment_image_view(key)
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

  def get_view_count(key)
    $redis.get(VIEWED_CAT_KEY + key).to_i
  end

  def increment_image_view(key)
    views = get_view_count(key)
    $redis.set((VIEWED_CAT_KEY + key), (views+1))
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