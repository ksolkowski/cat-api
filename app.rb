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

    def fake_response
      {"type"=>"interactive_message", "actions"=>[{"name"=>"aww", "type"=>"button", "value"=>"aww"}], "callback_id"=>"2ab45e8a0ff5d61a4ec257152b409b56e86ab005", "team"=>{"id"=>"T04T2GDGT", "domain"=>"wantable"}, "channel"=>{"id"=>"D2J26NNQG", "name"=>"directmessage"}, "user"=>{"id"=>"U050XHZV9", "name"=>"kevin"}, "action_ts"=>"1519872407.263251", "message_ts"=>"1519872405.000222", "attachment_id"=>"2", "token"=>"0f1X03bDgYgeWqGyqOZ3p6k6", "is_app_unfurl"=>false, "original_message"=>{"text"=>"", "bot_id"=>"B9C6LMCEN", "attachments"=>[{"fallback"=>"&lt;3 Cats &lt;3", "image_url"=>"https://cat--api.herokuapp.com/images/2ab45e8a0ff5d61a4ec257152b409b56e86ab005.jpg", "image_width"=>800, "image_height"=>533, "image_bytes"=>60383, "title"=>"Check out this cat", "id"=>1, "ts"=>1519872405, "color"=>"36a64f"}, {"callback_id"=>"2ab45e8a0ff5d61a4ec257152b409b56e86ab005", "fallback"=>"These cats are so cute.", "id"=>2, "actions"=>[{"id"=>"1", "name"=>"aww", "text"=>"aww", "type"=>"button", "value"=>"aww", "style"=>"primary"}, {"id"=>"2", "name"=>"dawww", "text"=>"dawww", "type"=>"button", "value"=>"dawww", "style"=>"danger"}]}], "type"=>"message", "subtype"=>"bot_message", "ts"=>"1519872405.000222"}, "response_url"=>"https://hooks.slack.com/actions/T04T2GDGT/322702357538/KDBIACHJwYaj6e5pWPPileAb", "trigger_id"=>"322822631461.4920557571.1c0fb85b51b7bf002fcc428571bd8820"}
    end

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

    r.post "action" do
      payload = JSON.parse(r.params["payload"])

      if payload["callback_id"] and already_saved?(payload["callback_id"].gsub(".jpg", ""))
        message = modify_original_message(payload)
        message
      # else
      #   payload.to_json
      end
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
          message = {
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
          }

          if r.params["text"] == "voting"
            test = {
              fallback: "These cats are so cute.",
              callback_id: clean_key(fake_path),
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
            message[:attachments].push test
          end

          message.to_json
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
      if already_saved?(cleaned_key)
        fetch_and_decode(cleaned_key)
      elsif random_key = fetch_all_stored_images.sample # idk pick some random cat
        fetch_and_decode(random_key)
      end
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