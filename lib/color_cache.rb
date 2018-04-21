module ColorCache
  include ColorDiff
  COLOR_KEY     = "colors:images:" # used by image instance to store all their colors
  HIGHEST_COLOR = "colors:highest:" # used for storing colors and what images have them {color-code: [image_ids]}

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def clear_colors
      $redis.keys(HIGHEST_COLOR + "*").map{|x| $redis.del(x) }.count
      $redis.keys(COLOR_KEY + "*").map{|x| $redis.del(x) }.count
    end

    def image_ids_by_color(color)
      $redis.smembers HIGHEST_COLOR + color
    end

    def all_color_keys
      @all_color_keys ||= $redis.keys(HIGHEST_COLOR + "*").map{|key| key.gsub(HIGHEST_COLOR, "") }
    end

    def populate_missing_colors
      all_image_ids = $redis.keys(COLOR_KEY + "*").map{|key| key.gsub(COLOR_KEY, "") }
      images = exclude(id: all_image_ids)
      total = images.count
      puts "found #{total} that need to be populated"
      images.each_with_index do |image, i|
        image.color_info
        puts "#{i+1}/#{total}" if (i+1) % 10 == 0
      end
    end

    def closest_stored_color(color)
      all_color_keys.min_by{|color_key| color_difference(color, color_key) }
    end

    def find_like_color(color)
      major_color_images = image_ids_by_color(color)
      @like_color ||= {}
      @used_images ||= Hash.new(0) # color: image_ids
      if major_color_images.empty?
        closet_color = @like_color[color]
        if closet_color.nil?
          closet_color = closest_stored_color(color)
          @like_color[color] = closet_color
        end
        major_color_images = image_ids_by_color(closet_color)
      end
      image_id = major_color_images.min_by{|id| @used_images[id] }
      @used_images[image_id] += 1
      image_id
    end

    def color_difference(color1, color2)
      rgb1 = ColorDiff::Color::RGB.new(*color1.split(",").map(&:to_i))
      rgb2 = ColorDiff::Color::RGB.new(*color2.split(",").map(&:to_i))

      ColorDiff.between(rgb1, rgb2)
    end
  end

  #
  # mapped_pixels:
  # [rows([[color, image_id])]
  def build_composite_image(mapped_pixels)
    mapped_saved_image_paths = []
    mapped_pixels.each_with_index do |row, i|
      mapped_saved_image_row = []

      row.each do |(color, row_image_id)|
        image = Image[row_image_id]
        mapped_saved_image_row << image.colorize_image(color)
      end

      puts "#{i+1}" if (i+1) % 10 == 0

      mapped_saved_image_paths << mapped_saved_image_row
    end

    puts "pre-generated images. now gunna save them."

    filenames = []
    new_image_height = mapped_saved_image_paths.count
    new_image_width = mapped_saved_image_paths.first.count
    mapped_saved_image_paths.each_with_index do |row_images, i|
      filename = "tmp/composite_#{id}_#{i}.jpg"
      MiniMagick::Tool::Montage.new do |montage|
        row_images.each do |image_path|
          montage << image_path
        end

        puts "#{i+1}" if (i+1) % 10 == 0

        montage.geometry "+0+0"

        montage.tile "#{row_images.count}x1" # width x height

        montage << filename
      end

      filenames << filename
    end

    puts "combined all them images now making one big one"

    MiniMagick::Tool::Montage.new do |montage|
      filenames.each do |filename|
        montage << filename
      end

      montage.geometry "+0+0"
      montage.tile "1x#{filenames.count}" # width x height
      montage << "tmp/end_composite_#{id}.jpg"
    end

  end

  def do_all
    mapped = find_and_map_similar_images
    puts "built the map"
    build_composite_image(mapped)
  end

  # https://github.com/nazarhussain/camalian

  def find_and_map_similar_images
    image = MiniMagick::Image.read(decoded_image)
    shrunk_image = image.combine_options{|x| x.resize "#{width/5}x" }
    pixels = shrunk_image.get_pixels
    shrunk_image.destroy!
    mapped_pixels = [] # pixel to image id
    total = pixels.count # IS THE HEIGHT
    puts "looking at #{total} height and #{pixels.first.count} width"

    pixels.each_with_index do |row, i|
      i = (i+1)
      mapped_row = []
      row.each do |column|
        # color_string = column.join(",")
        color_string = column.map{|x| x.round(-1) }.join(",") # round to nearest 10
        like_color_id = Image.find_like_color(color_string)
        mapped_row << [color_string, like_color_id]
      end

      puts "#{i}/#{total}" if i % 10 == 0

      mapped_pixels << mapped_row
    end

    #image.destroy!

    mapped_pixels
  end

  # returns array
  # [rgb, percentage]
  def highest_color_by_percentage
    color_info.max_by{|color, percentage| percentage }
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

    # rgb code -> percentage
    colors = output.split("\n").map do |line|
      num_pixels, color_info = line.strip.split(":")

      hex_code, rgb_code = color_info.split(/(\#.+)/).last.split(" ") # #06639B srgb(6,99,155)
      percentage = (num_pixels.to_f / total_pixels).round(4)

      # {num_pixels: num_pixels, hex_code: hex_code, rgb_code: rgb_code, percentage: percentage}

      # [0.XXX, "XXX, XXX, XXX"]
      [rgb_code.split(/\((.*)\)/).last, percentage]
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

  def colorize_image(fill_color=nil)
    fill_color ||= highest_color_by_percentage.first
    fill = "rgb(#{fill_color})"
    size = ""
    filename = "tmp/#{id}_#{fill_color.gsub(",", "_")}_converted.jpg"
     # if the image doesn't exist in tempfile try and build it from the ids
    unless File.exists?(filename)
      # image doesn't exist already
      image = MiniMagick::Image.read(decoded_image)
      content = MiniMagick::Tool::Convert.new do |convert|
        convert << image.path
        convert.fill fill
        convert.colorize "75%"
        convert.resize "50x50^"
        convert.gravity "center"
        convert.crop "50x50+0+0"
        convert << filename
      end
    end

    filename
  end

  def clear_color_cache
    $redis.del(color_key)
  end

  private

  def color_key
    COLOR_KEY + self.id.to_s
  end
end