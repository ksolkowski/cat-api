module ColorCache
  COLOR_KEY     = "colors:images:" # used by image instance to store all their colors
  HIGHEST_COLOR = "colors:images:ids:" # used for storing colors and what images have them {color-code: [image_ids]}

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def image_ids_by_color(color)
      $redis.smembers HIGHEST_COLOR + color
    end
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
    total_pixels = image.dimensions.inject(:*)
    path = image.path
    output = %x(convert #{path} -colors 8 -format "%c" histogram:info:)

    # rbg code -> percentage
    colors = output.split("\n").map do |line|
      num_pixels, color_info = line.strip.split(":")

      hex_code, rbg_code = color_info.split(/(\#.+)/).last.split(" ") # #06639B srgb(6,99,155)
      percentage = (num_pixels.to_f / total_pixels).round(4)

      # {num_pixels: num_pixels, hex_code: hex_code, rbg_code: rbg_code, percentage: percentage}

      # [0.XXX, "XXX, XXX, XXX"]
      [rbg_code.split(/\((.*)\)/).last, percentage]
    end.sort_by(&:last).reverse

    image.destroy! # remove tempfile

    $redis.pipelined do
      colors.each_with_index do |(color_code, percentage), index|
        $redis.zadd(color_key, percentage, color_code)
      end
      color_code, percent = colors.max_by(&:last)
      $redis.sadd((HIGHEST_COLOR + color_code), id)
    end

    colors.to_h
  end

  def clear_color_cache
    $redis.del(color_key)
  end

  private

  def color_key
    COLOR_KEY + self.id.to_s
  end
end