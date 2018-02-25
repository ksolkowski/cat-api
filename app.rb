# ./app.rb
require "roda"
require 'redis'
require 'json'
require 'open-uri'

require_relative "./cat_roamer"

uri = URI.parse(ENV["REDIS_URL"]||"redis://localhost:6379")
$redis = Redis.new(host: uri.host, port: uri.port, password: uri.password)
ENV["SITE_URL"] ||= "localhost:3000"
ENV["RACK_ENV"] ||= "development"

class CatApi < Roda
  include CatRoamer
  NO_CAT_LIST = ['austinkahly', 'murph', 'nichelle']

  plugin :json

  route do |r|

    r.root do
      "hello"
    end

    r.on "stats" do
      get_cat_stats
      "#{@images_saved} images in redis. #{@urls_saved} urls in redis. #{@views}"
    end

    r.on "cats.jpg" do
      response['Content-Type'] = "image/jpeg"
      decoded_image, fake_path = fetch_or_download_cat_urls
      decoded_image
    end

    r.on "cats" do
      if r.is_get?
        response['Content-Type'] = "image/jpeg"
        decoded_image, fake_path = fetch_or_download_cat_urls
        decoded_image
      else
        response['Content-Type'] = 'application/json'
        if NO_CAT_LIST.include?(r.params["user_name"]) and r.params["text"] != "cats are great"
          # mj cat http://nbacatwatch.com/wp-content/uploads/2017/10/f98a5f820283e9fada580d5f6d2f3e81.jpg
          {
            response_type: "in_channel",
            text: "Come back when you have a cat"
          }
        else
          decoded_image, fake_path = fetch_or_download_cat_urls

          real_url = File.join ENV["SITE_URL"], 'images', fake_path
          clear_cached_cats if r.params["text"] == "clear"
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
      count = clear_cached_cats
      "cleared #{count} images"
    end

    r.on "images" do
      cleaned_key = request.remaining_path[1..-1].gsub(".jpg", "")
      response['Content-Type'] = "image/jpeg"
      fetch_and_decode(cleaned_key) if already_saved?(cleaned_key)
    end

    # idk just give a random image
    r.get do
      if random_key = fetch_all_stored_images.sample # idk pick some random cat
        response['Content-Type'] = "image/jpeg"
        fetch_and_decode(random_key)
      end

    end

  end
end