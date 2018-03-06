class Image < Sequel::Model
  plugin :validation_helpers

  def before_create
    self.hashed_key = Digest::SHA1.hexdigest(self.original_url)
    self.encoded_image = Base64.encode64(open(self.original_url).read)
    super
  end

  def validate
    super
    validates_presence :original_url
  end

  def decoded_image
    Base64.decode64 encoded_image
  end

  def self.save_and_store_urls(urls)
    urls.each do |url|
      image = Image.new(original_url: url)
      image.save
    end
  end

end