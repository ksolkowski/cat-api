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
  task cycle_cat_images: :app do
    include CatRoamer
    clear_and_store_cat_keys
  end

  desc "cleans dup imagse"
  task clean_dup_images: :app do
    dups = DB["select regexp_replace(images.original_url, 'http|https' ,'', 'g') as url from images"].
    map(:url).group_by{|x| x }.reject{|x,y| y.count == 1 }.values
    puts "found #{dups.count} dup cat urls"
    dups.each do |dup_urls|
      url = dup_urls.first
      Image.where(Sequel.like(:original_url, "%" + url)).each do |image|
        next if image.original_url.include?("https:")
        image.destroy
      end
    end
  end

  task clean_original_urls: :app do
    Image.where(Sequel.like(:original_url, "http%")).each do |image|
      new_url = image.original_url.gsub(/(http|https):\/\//, "")
      image.original_url = new_url
      image.save(validate: false)
    end
  end

  task save_mj_cat: :app do
    url = "http://nbacatwatch.com/wp-content/uploads/2017/10/f98a5f820283e9fada580d5f6d2f3e81.jpg"
    Image.new(original_url: url).save
  end

  desc "fetches and saves cats into the database and sets their hashed_keys in redis"
  task save_and_set_cats: :app do
    random_pages = (0..2010).to_a.sample(5) # just pick a number
    puts "fetching and storing cats from #{random_pages}"

    all_cat_urls = random_pages.map do |page|
      html = Nokogiri::HTML(open("http://d.hatena.ne.jp/fubirai/?of=#{page}"))
      cat_urls = html.css("img.hatena-fotolife").to_a.map{|child| child.attributes["src"].value }
      puts "grabbing: #{cat_urls.count} urls from page: #{page}"
      sleep(10)
      cat_urls
    end.flatten.select{|url| url.include?("https") }

    mapped_urls = all_cat_urls.inject({}){|h,x| h[x]=x.gsub(/(http|https):\/\//, "");h }
    # remove dups
    already = Image.where(original_url: mapped_urls.values).select_map(:original_url)

    puts "chekcing #{mapped_urls.keys.count} url"
    mapped_urls.reject! do |k, v|
      already.include?(v)
    end

    puts "saving #{mapped_urls.keys.count} new urls"

    Image.save_and_store_urls(mapped_urls.keys)
  end
end