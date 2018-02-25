require "rake"
require "rake/clean"
require "rdoc/task"

require "./app"

task :pre_fetch_cats do
  include CatRoamer

  old_cat_urls = $redis.smembers(URL_KEY)

  puts "old_cat_urls: #{old_cat_urls}"
  random_pages = (0..2010).to_a.sample(10) # just pick a number
  puts "fetching and storing cats from #{random_pages}"

  all_cat_urls = random_pages.map do |page|
    html = Nokogiri::HTML(open("http://d.hatena.ne.jp/fubirai/?of=#{page}"))
    cat_urls = html.css("img.hatena-fotolife").to_a.map{|child| child.attributes["src"].value }
    puts "grabbing: #{cat_urls.count} urls from page: #{page}"
    sleep(1)
    cat_urls
  end.flatten.reject do |url|
    old_cat_urls.include?(url) # don't want the same url mann
  end

  new_cat_urls = all_cat_urls.sample(50)

  puts "storing #{new_cat_urls} to cache"

  new_cat_urls.each_with_index do |url, i|
    puts "#{i}/#{new_cat_urls.count}"

    # remove an old image
    unless old_cat_urls.empty?
      old_url = old_cat_urls.pop
      remove_url_and_image(old_url)
    end

    break if $redis.info["used_memory"].to_i > 25000000 and ENV["RACK_ENV"] != "development"
    save_image_in_redis(url)
    sleep(1)
  end

  # make sure all the old ones are gone
  while !old_cat_urls.empty? do
    old_url = old_cat_urls.pop
    remove_url_and_image(old_url)
  end

end