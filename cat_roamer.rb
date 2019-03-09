require 'base64'
require 'open-uri'
require 'nokogiri'
module CatRoamer
  STORED_HASH_KEY  = "cats:images"  # redis set [encoded_keys]
  VOTING_CAT_KEY   = "cats:voting"  #
  AWW   = "aww"
  DAWWW = "dawww"
  COMBINED = "combined:"
  VERSION = "v1"

  DEFAULT_TILING = {
    1 => "1x1",
    2 => "2x1",
    3 => "3x1",
    4 => "2x2",
    5..6 => "3x2",
    7..8 => "4x2",
    9 => "3x3",
    10..12 => "4x3",
    13..15 => "5x3",
    16..20 => "5x4",
    21..24 => "6x4",
    25 => "5x5",
    26..30 => "6x5",
    31..36 => "7x5",
    31..35 => "7x5",
    36 => "6x6",
    37..42 => "7x6",
    43..48 => "8x6"
  }


def adjust_image_count(count)
  range, tile = DEFAULT_TILING.find{|x, y| x == count or (x.is_a?(Range) and x.include?(count)) }

  return 12 if range.nil?

  # if it's a range and not the top number
  if range.is_a?(Range)
    count = range.max
  end

  count
end

  def fetch_random_cat
    hashed_key = $redis.srandmember(STORED_HASH_KEY)
    if hashed_key
      Image.find_by_hashed_key(hashed_key)
    end
  end

  def is_member?(hashed_key)
    $redis.sismember(STORED_HASH_KEY, hashed_key)
  end

  def encode_multiple_url(joined_ids)
    Base64.encode64(joined_ids)
  end

  def decode_multiple_url(url)
    Base64.decode64(url)
  end

  def gif_some_cats(count=10, cleaned_key=nil)
    size = "600x600"

    if !cleaned_key.nil?
      joined_ids = Base64.decode64(cleaned_key)

      ids = joined_ids.split("_").map(&:to_i)

      images = Image.where(id: ids).all
    else
      images = Image.random(count).all

      joined_ids = images.map(&:id).join("_")
    end

    encoded_filename = Base64.encode64(joined_ids).gsub("\n", "=NO")

    output_filename = "tmp/#{encoded_filename}.gif"

    if !File.exists?(output_filename)
      file_names = images.map.with_index do |image, index|
        filename = "tmp/gifs_#{size}_#{index}.jpg"
         # if the image doesn't exist in tempfile try and build it from the ids
        # image doesn't exist already
        if File.exists?(filename)
          filepath = filename
        else
          filepath = MiniMagick::Image.read(image.decoded_image).path
        end

        content = MiniMagick::Tool::Convert.new do |convert|
          convert << filepath
          convert.resize "#{size}^"
          convert.gravity "center"
          convert.crop "#{size}+0+0"
          convert << filename
        end

        filename
      end

      output = %x(convert -delay 30 -loop 0 #{file_names.join(" ")} #{output_filename})
    end

    url = File.join ENV["SITE_URL"], 'gifs', VERSION, (encoded_filename + ".gif")
    {filename: output_filename, url: url}
  end

  # responds with a raw blob
  def combine_some_cats(count=6)
    count = count.abs
    count = 30 if count >= 30
    count = 2 if count == 1

    size = Image.group_and_count(:width, :height).all.select{|x| x[:count] > 100 }.sample
    images = Image.random(count).where{width =~ size.width}.where{height =~ size.height}.all
    joined_ids = images.map(&:id).join("_")
    #encoded = encode_multiple_url(joined_ids)
    url = File.join ENV["SITE_URL"], 'images', VERSION, (COMBINED + joined_ids + ".jpg")

    filename = "tmp/#{joined_ids}.jpg"

    if count >= 10
      blob = "blob"
    else
      begin
        image = MiniMagick::Image.open(filename)
      rescue => e
        # image doesn't exist already
        image = build_montage(images, filename)
      end

      blob = image.to_blob
      image.destroy! # kill that tempfile
    end

    {blob: blob, filename: filename, url: url}
  end

  def open_combined_image(cleaned_key)
    cleaned_key.gsub!(COMBINED, "")

    if cleaned_key.include?(VERSION)
      cleaned_key = cleaned_key.split("#{VERSION}/").last
    end

    filename = "tmp/#{cleaned_key}.jpg"

    ids = cleaned_key.split("_")

    # if the image doesn't exist in tempfile try and build it from the ids
    begin
      image = MiniMagick::Image.open(filename)
    rescue => e
      # image doesn't exist already
      images = Image.where(id: ids).all
      image = build_montage(images, filename)
    end

    blob = image.to_blob
    image.destroy! # kill that tempfile
    blob
  end

  def build_montage(images, filename)
    MiniMagick::Tool::Montage.new do |montage|
      images.each do |image|
        montage << MiniMagick::Image.read(image.decoded_image).path
      end
      montage.geometry "+0+0"
      montage << filename
    end

    MiniMagick::Image.open(filename)
  end

  # response
    # {
    #   "type"=>"interactive_message",
    #   "actions"=>[{"name"=>"recommend", "type"=>"button", "value"=>"recommend"}],
    #   "callback_id"=>"fc019dbcdca7bbba4439c990d0127e708254743d.jpg",
    #   "team"=>{"id"=>"T04T2GDGT", "domain"=>"wantable"}, "channel"=>{"id"=>"D2J26NNQG", "name"=>"directmessage"},
    #   "user"=>{"id"=>"U050XHZV9", "name"=>"kevin"},
    #   "action_ts"=>"1519690770.689609",
    #   "message_ts"=>"1519690768.000289",
    #   "attachment_id"=>"2",
    #   "token"=>"0f1X03bDgYgeWqGyqOZ3p6k6",
    #   "is_app_unfurl"=>false,
    #   "original_message"=>{
    #     "text"=>"", "bot_id"=>"B9C6LMCEN",
    #     "attachments"=>[
    #       {
    #         "fallback"=>"&lt;3 Cats &lt;3", "image_url"=>"https://cat--api.herokuapp.com/images/fc019dbcdca7bbba4439c990d0127e708254743d.jpg",
    #         "image_width"=>533, "image_height"=>800, "image_bytes"=>80580, "title"=>"Check out this cat", "id"=>1, "ts"=>1519690768, "color"=>"36a64f"
    #       },
    #       {
    #         "callback_id"=>"fc019dbcdca7bbba4439c990d0127e708254743d.jpg", "fallback"=>"These cats are so cute.",
    #         "id"=>2,
    #         "actions"=>[
    #           {"id"=>"1", "name"=>"recommend", "text"=>"Recommend", "type"=>"button", "value"=>"recommend", "style"=>"primary"},
    #           {"id"=>"2", "name"=>"no", "text"=>"No", "type"=>"button", "value"=>"bad", "style"=>"danger"}
    #         ]
    #       }
    #     ],
    #     "type"=>"message", "subtype"=>"bot_message", "ts"=>"1519690768.000289"
    #   },
    #   "response_url"=>"https://hooks.slack.com/actions/T04T2GDGT/322306029399/HcNjaRaw6yIwS6xmUSlm6XqL",
    #   "trigger_id"=>"322102643078.4920557571.0c5718dab274953c5044f88938378511"
    # }
  def modify_original_message(payload)
    original_message = payload["original_message"]
    callback_id      = payload["callback_id"]
    action_button    = payload['actions'].first # what button was pressed
    attachment_id    = payload["attachment_id"].to_s
    user             = payload["user"]

    original_attachment = original_message['attachments'].find{|x| x["id"].to_s == attachment_id }

    original_attachment["actions"].sort_by{|btn| btn["value"] == action_button["value"] ? 0 : 1 }.each do |btn|
      vote_key = btn["value"] == AWW ? AWW : DAWWW
      store_or_remove_user_vote(callback_id, user, vote_key) if btn["value"] == action_button["value"] # this is the action

      votes = vote_count(callback_id, vote_key)
      if votes > 0
        btn["text"] = "#{vote_key} (#{votes})"
      else
        btn["text"] = vote_key
      end

      btn
    end

    original_message["replace_original"] = true
    original_message
  end

  def vote_count(callback_id, vote_key)
    $redis.scard("#{VOTING_CAT_KEY}:#{vote_key}:#{callback_id}") # return the count
  end

  def store_or_remove_user_vote(callback_id, user, vote_key)
    user_id   = user["id"]
    set_key   = "#{VOTING_CAT_KEY}:#{vote_key}:#{callback_id}"
    other_key = "#{VOTING_CAT_KEY}:#{(vote_key == AWW ? DAWWW : AWW)}:#{callback_id}"
    # if they are a member of other key remove the vote and add a vote
    if $redis.sismember(other_key, user_id)
      $redis.srem(other_key, user_id)
      $redis.sadd(set_key, user_id)
    elsif $redis.sismember(set_key, user_id) # remove vote
      $redis.srem(set_key, user_id)
    else
      $redis.sadd(set_key, user_id)
    end
  end

  def set_stored_keys(keys)
    $redis.del STORED_HASH_KEY
    $redis.sadd STORED_HASH_KEY, keys
  end

  def clear_and_store_cat_keys
    Image.where(hashed_key: $redis.smembers(STORED_HASH_KEY)).each do |image|
      $redis.del("#{VOTING_CAT_KEY}:#{AWW}:#{image.hashed_key}")
      $redis.del("#{VOTING_CAT_KEY}:#{DAWWW}:#{image.hashed_key}")
    end

    keys = Image.random(100).map(:hashed_key)
    set_stored_keys(keys)
  end

end