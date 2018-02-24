# ./app.rb
require "roda"
require 'redis'
require 'json'

require_relative "./cat_roamer"

uri = URI.parse(ENV["REDIS_URL"]||"redis://localhost:6379")
$redis = Redis.new(host: uri.host, port: uri.port, password: uri.password)
ENV["SITE_URL"] ||= "localhost:3000"

class CatApi < Roda
  include CatRoamer
  NO_CAT_LIST = ['austinkahly', 'murph', 'nichelle']

  plugin :json

  route do |r|

    r.root do

      "hello"
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
          {
            response_type: "in_channel",
            text: "Come back when you have a cat"
          }
        else
          decoded_image, fake_path = fetch_or_download_cat_urls

          real_url = File.join ENV["SITE_URL"], fake_path
          clear_cached_cats if r.params["text"] != "clear"
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


    r.get do
      cleaned = request.remaining_path[1..-1].gsub(".jpg", "")
      key = cleaned_path_to_key(cleaned)
      response['Content-Type'] = "image/jpeg"

      if already_saved?(key)
        fetch_and_decode(key)
      else # idk pick some random cat
        random_key = $redis.keys(STORED_IMAGE_KEY + "*").sample
        fetch_and_decode(random_key)
      end

    end

  end
end