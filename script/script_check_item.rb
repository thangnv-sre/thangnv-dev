require 'csv'

# read csv file that have title in first line and convert to array of integer

files = Dir["file/*"]
push_file = []
@production_config = YAML.load(ERB.new(File.read("#{Rails.root}/config/aws/production.yml")).result)['footage']['s3']['backup_bucket'].freeze and true
FOOTAGE_SIZE_CONFIG = YAML.load(ERB.new(File.read("#{Rails.root}/config/footage_size.yml")).result).freeze and true

files.each do |file|
  puts file

  item_ids = CSV.read(file, headers: true).map { |row| row['item_id'].to_i } and true
  # get item data from the list of item_ids with the fields we need: id, language
  footages = []
  items = []
  item_ids.each_slice(1000) do |item_ids_slice|
    footages += Footage.where(item_id: item_ids_slice).pluck(:item_id, :aws_region_code, :container_type) and true
    items += Item.where(id: item_ids_slice).pluck(:id, :height, :width) and true
  end
  footages.uniq! and true
  items.uniq! and true

  puts footages.count

  @footage_hash = {}
  @products = {}
  Product.all.each do |product|
    @products[product.size_name] = product[:size_no]
  end and true



  footages.each do |item_id, aws_region_code, container_type|
    @footage_hash[item_id] = {}
    @footage_hash[item_id][:aws_region_code] = aws_region_code
    @footage_hash[item_id][:container_type] = container_type
  end and true
  items.each do |item_id, height, width, price_group_no|
    if !@footage_hash[item_id].nil?
      @footage_hash[item_id][:height] = height
      @footage_hash[item_id][:width] = width
    else
      puts "item_id: #{item_id} not found in footage"
    end
  end and true



  def product_directory(item_id)
    "product/#{(item_id / 1_000_000)}/#{(item_id / 1000) % 1000}/#{item_id}"
  end

  def backup_bucket_name(aws_region_code)
    @production_config[aws_region_code]
  end

  def original_size_info(height, width)
    FOOTAGE_SIZE_CONFIG["original_sizes"].select {|_h| _h["height"] == height && _h["width"] == width }.first
  end

  def original_size_name(hight, width)
    original_size_info(hight, width)["name"]
  end

  def size_no(height, width)
    @products[original_size_name(height, width)]
  end

  def product_path(item_id)
    size_no = size_no(@footage_hash[item_id][:height], @footage_hash[item_id][:width])
    container_type = @footage_hash[item_id][:container_type]
    product_ext = FOOTAGE_CONTAINER_TYPE_NAME_HASH[container_type]
    "#{product_directory(item_id)}/#{item_id}-#{size_no}.#{product_ext}"
  end

  puts @footage_hash.count

  #wirte to csv file, create if not exist
  @production_config.keys.each do |aws_region_code|  
    push_file << "ng_footage_link_to_restore_in_#{aws_region_code}_region.csv" unless push_file.include?("ng_footage_link_to_restore_in_#{aws_region_code}_region.csv")
    CSV.open("ng_footage_link_to_restore_in_#{aws_region_code}_region.csv", "a") do |csv|
      item_ids.each do |item_id|
        if @footage_hash[item_id] && @footage_hash[item_id][:aws_region_code] == aws_region_code
          backup_bucket = backup_bucket_name(@footage_hash[item_id][:aws_region_code])
          product = product_path(item_id)
          csv << [backup_bucket, product]
        end
      end
    end
  end
end

s3 = AWS::S3.new()
push_file.each do |file|
  object = s3.buckets["pixta-scripts-stg"].objects["sre_scripts/#{file}"]
  object.write(File.open(file))
end