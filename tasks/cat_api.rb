require "rake"
require "rake/clean"
require "rdoc/task"
namespace :cat_api do

  desc "clears all cat redis values"
  task clear_redis: :app do
     $redis.keys("cats:*").each do |key|
      puts "clearing #{key}"
      $redis.del(key)
    end
  end

  desc "sets width and height of saved images"
  task set_sizes: :app do
    Image.where(height: nil, width: nil).each do |image|
      image.height = image.sizes.height
      image.width = image.sizes.width
      image.save
    end
  end

  desc "cycles the available cat images"
  task save_mj_cat: :app do
    clear_and_store_cat_keys
  end

  task save_mj_cat: :app do
    url = "http://nbacatwatch.com/wp-content/uploads/2017/10/f98a5f820283e9fada580d5f6d2f3e81.jpg"
    Image.new(original_url: url).save
  end

  desc "fetches and saves cats into the database and sets their hashed_keys in redis"
  task save_and_set_cats: :app do
    include CatRoamer
    old_cat_urls = $redis.smembers STORED_HASH_KEY
    random_pages = (0..2010).to_a.sample(5) # just pick a number
    puts "fetching and storing cats from #{random_pages}"

    all_cat_urls = random_pages.map do |page|
      html = Nokogiri::HTML(open("http://d.hatena.ne.jp/fubirai/?of=#{page}"))
      cat_urls = html.css("img.hatena-fotolife").to_a.map{|child| child.attributes["src"].value }
      puts "grabbing: #{cat_urls.count} urls from page: #{page}"
      sleep(10)
      cat_urls
    end.flatten.reject do |url|
      old_cat_urls.include?(url) # don't want the same url mann
    end
    # remove dups
    all_cat_urls = (all_cat_urls - Image.where(original_url: all_cat_urls).select_map(:original_url))
    images = Image.save_and_store_urls(all_cat_urls)
  end
end