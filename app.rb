# ./app.rb
require "roda"
require "redis"
require "json"
require "open-uri"
require "sequel"
require "image_size"
require "mini_magick"

ENV["SITE_URL"] ||= "https://catapi.localtunnel.me"
ENV["RACK_ENV"] ||= "development"

if ENV['RACK_ENV'] == "production"
  DB = Sequel.connect(ENV["DATABASE_URL"])
else
  user     = 'root'
  password = 'pass'
  database = 'cat--api'
  DB = Sequel.connect(adapter: "postgres", database: database, host: "127.0.0.1", user: user, password: password)
end

uri = URI.parse(ENV["REDIS_URL"]||"redis://localhost:6379")
$redis = Redis.new(host: uri.host, port: uri.port, password: uri.password)

require_relative "./cat_roamer"
require_relative './models/image.rb'

class CatApi < Roda
  include CatRoamer
  NO_CAT_LIST = ['austinkahly', 'murph', 'nichelle']

  plugin :json

  route do |r|

    r.root do
      "hello"
    end

    r.on "all_cats" do
      size = Image.group_and_count(:width, :height).all.select{|x| x[:count] > 100 }.sample

      images = Image.random(20).where{width =~ size.width}.where{height =~ size.height}.all

      width  = (size.width / 4)
      height = (size.height / 4)
      images.map{|image| "<img src=\"data:image/jpg;base64,#{image.encoded_image}\" width=\"#{width}\" height=\"#{height}\"></img>" }.
      each_slice(5).to_a.map{|x| x.join("") }.join("<br>")
    end

    r.on "stats" do
      "#{Image.count} images in database. #{$redis.scard(STORED_HASH_KEY)} images in cache"
    end

    r.on "cats.jpg" do
      response['Content-Type'] = "image/jpeg"
      fetch_random_cat.decoded_image
    end

    r.post "action" do
      payload = JSON.parse(r.params["payload"])

      if payload["callback_id"] and is_member?(payload["callback_id"])
        message = modify_original_message(payload)
        message
      else
        {
          response_type: "ephemeral",
          replace_original: false,
          text: "Voting has closed."
        }
      end
    end

    r.on "combine" do
      response['Content-Type'] = "image/jpeg"
      combination = combine_some_cats
      combination[:blob] # responds with the created image blob
    end

    r.get "cats" do
      response['Content-Type'] = "image/jpeg"

      fetch_random_cat.decoded_image
    end

    r.post "cats" do
      response['Content-Type'] = 'application/json'
      text = r.params["text"]
      rude = false

      if text.include?("lots") and !NO_CAT_LIST.include?(r.params["user_name"])
        count = text.split("lots").last
        rude = !(count =~ /\D/).nil?

        title = "Why you have to be so rude"
      end

      if !rude and text.include?("lots") and !NO_CAT_LIST.include?(r.params["user_name"])
        count = text.split("lots").last
        count ||= 12

        begin
          count = adjust_image_count(count.to_i)
        rescue => e
          count = 12
        end

        image = combine_some_cats(count)

        ts = Time.now.to_i
        message = {
          response_type: "in_channel",
          attachments: [
            {
              fallback: "<3 Cats <3",
              color: "#36a64f",
              title_link: "Cats",
              fields: [],
              image_url: image[:url],
              thumb_url: image[:url],
              ts: ts
            }
          ]
        }
      else
        if rude or NO_CAT_LIST.include?(r.params["user_name"]) and text != "cats are great"
          image = Image.find_by_hashed_key(Image::MJ_HASHED_KEY)
          title = "Come back when you have a cat" if !rude
        else
          image = fetch_random_cat || Image.random()

          title = "Check out this cat"
          buttons = {
            fallback: "These cats are so cute.",
            callback_id: image.hashed_key,
            actions: [
              {
                name: "aww",
                text: AWW,
                type: "button",
                value: AWW,
                style: "primary"
              },
              {
                name: "dawww",
                text: DAWWW,
                type: "button",
                value: DAWWW,
                style: "danger"
              }
            ]
          }
        end
        message = {
          response_type: "in_channel",
          attachments: [
            {
              fallback: "<3 Cats <3",
              color: "#36a64f",
              title: title,
              title_link: "Cats",
              fields: [],
              image_url: image.url,
              thumb_url: image.url,
              ts: Time.now.to_i
            }
          ]
        }
      end

      message[:attachments].push(buttons) unless buttons.nil?

      message.to_json
    end

    r.on "images" do
      cleaned_key = request.remaining_path[1..-1].gsub(".jpg", "")
      response['Content-Type'] = "image/jpeg"
      if cleaned_key.start_with?(COMBINED) or (cleaned_key.include?(COMBINED) and cleaned_key.include?(VERSION))
        open_combined_image(cleaned_key)
      else
        if image = Image.find_by_hashed_key(cleaned_key)
          image.decoded_image
        elsif random_cat = fetch_random_cat
          random_cat.decoded_image
        end
      end
    end

    # idk just give a random image
    r.get do
      if random_cat = fetch_random_cat
        response['Content-Type'] = "image/jpeg"
        random_cat.decoded_image
      end
    end

  end
end