class Image < Sequel::Model
  MJ_HASHED_KEY = "082fc1f97d88b237855e05a01dba0f209ecca55c"
  COLOR_KEY = "colors:"
  plugin :validation_helpers

  def before_create
    data = open(self.original_url)
    self.encoded_image = Base64.encode64(data.read)
    self.hashed_key    = Digest::SHA1.hexdigest(self.original_url)
    self.width  = sizes.width
    self.height = sizes.height
    super
  end

  def validate
    super
    validates_presence :original_url
  end

  def self.find_by_hashed_key(hashed_key)
    Image.where(hashed_key: hashed_key).first
  end

  def color_info
    return @color_info unless @color_info.nil?
    # grab all of them
    colors = $redis.zrange(color_key, 0, -1, with_scores: true).to_h
    if colors.empty?
      colors = store_color_infomation
    end

    @color_info = colors
  end

  def store_color_infomation
    image = MiniMagick::Image.read(decoded_image)
    total_pixels = image.data["pixels"]
    path = image.path
    output = %x(convert #{path} -colors 8 -format "%c" histogram:info:)


    # rbg code -> percentage
    colors = output.split("\n").map do |line|
      num_pixels, color_info = line.strip.split(":")

      hex_code, rbg_code = color_info.split(/(\#.+)/).last.split(" ") # #06639B srgb(6,99,155)
      percentage = (num_pixels.to_f/total_pixels).round(4)

      #{num_pixels: num_pixels, hex_code: hex_code, rbg_code: rbg_code, percentage: percentage}

      # [0.XXX, "XXX, XXX, XXX"]
      [rbg_code.split(/\((.*)\)/).last, percentage]
    end.sort_by(&:last).reverse

    image.destroy! # remove tempfile

    $redis.pipelined do
      colors.each do |color_code, percentage|
        $redis.zadd(color_key, percentage, color_code)
      end
    end

    colors.to_h
  end

  def self.random(limit=1)
    images = Image.exclude(hashed_key: MJ_HASHED_KEY).order(Sequel.lit('RANDOM()')).limit(limit)
    if limit == 1
      images.first
    else
      images
    end
  end

  def self.save_and_store_urls(urls, nap_length=5)
    urls.map do |url|
      image = Image.new(original_url: url)
      image.save
      sleep nap_length
      image
    end
  end

  def decoded_image
    Base64.decode64 encoded_image
  end

  def url
    File.join ENV["SITE_URL"], 'images', hashed_key
  end

  def sizes
    @sizes ||= ImageSize.new(decoded_image)
  end

  def clear_color_cache
    $redis.del(color_key)
  end

  private

  def color_key
    COLOR_KEY + self.id.to_s
  end

end