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
  # clear out old images
  puts "removing #{old_cat_urls.count} old cat images"

  new_cat_urls = []
  random_pages.each do |page|
    html = Nokogiri::HTML(open("http://d.hatena.ne.jp/fubirai/?of=#{page}"))
    cat_urls = html.css("img.hatena-fotolife").to_a.map{|child| child.attributes["src"].value }

    puts "storing: #{cat_urls.count} urls from page: #{page}"
    new_cat_urls << cat_urls

    puts "used_memory: #{$redis.info["used_memory"]} human: #{$redis.info["used_memory_human"]}"

    cat_urls.each do |url|
      # remove an old image
      unless old_cat_urls.empty?
        old_url = old_cat_urls.pop
        $redis.del url_to_redis_key(old_url)
        remove_cat_url(url)
      end

      break if $redis.info["used_memory"].to_i > 25000000 and ENV["RACK_ENV"] != "development"
      save_image_to_redis(url)
      store_cat_url(url)
    end

    break if $redis.info["used_memory"].to_i > 25000000 and ENV["RACK_ENV"] != "development"
    sleep(15)
    puts "memory usage: #{$redis.info["used_memory_human"]}"
  end

  puts "storing #{new_cat_urls} new cat image urls"

end