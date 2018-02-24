require "rake"
require "rake/clean"
require "rdoc/task"

require "./app"

task :pre_fetch_cats do
  include CatRoamer

  random_pages = (0..2010).to_a.sample(5)
  puts "fetching and storing cats from #{random_pages}"
  old_cat_urls = $redis.get(STORE_KEY)

  if old_cat_urls.nil?
    old_cat_urls = []
  else
    old_cat_urls = JSON.parse(old_cat_urls)
  end
  puts "old_cat_urls: #{old_cat_urls}"
  new_cat_urls = []
  random_pages.each do |page|
    html = Nokogiri::HTML(open("http://d.hatena.ne.jp/fubirai/?of=#{page}"))
    cat_urls = html.css("img.hatena-fotolife").to_a.map{|child| child.attributes["src"].value }

    puts "storing: #{cat_urls.count} urls from page: #{page}"
    new_cat_urls << cat_urls

    cat_urls.each do |url|
      save_image_to_redis(url)
    end
    sleep(30)
    used_memory = $redis.info["used_memory"]
    puts "memory usage: #{used_memory}"
    break if used_memory.to_i > 28000000
  end

  puts "storing #{new_cat_urls} new cat image urls"
  store_cat_urls(new_cat_urls.flatten)

  # clear out old images
  puts "removing #{old_cat_urls.count} old cat images"
  old_cat_urls.each do |url|
    key = url_to_redis_key(url)
    $redis.del(key)
  end


end