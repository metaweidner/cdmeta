require 'open-uri'
require 'fileutils'
require 'json'
require 'nokogiri'
require 'yaml'
require './cdmeta_methods'

config = YAML::load_file(File.join(__dir__, 'config.yml'))

server = config['cdm']['server']
port = config['cdm']['port']
cdm_url = "http://#{server}:#{port}/dmwebservices/index.php?q="

meta_map_config = config['meta_map']
meta_map = meta_map_to_hash(meta_map_config)
collections_config = config['collections']
collection_titles = collections_to_hash(collections_config)

puts "\nDownloading Repository Metadata\n"
collection_count = 0
total_object_count = 0

collection_alias = "p15195coll11"

# collections = get_collections(cdm_url)
# collection_aliases = get_collection_aliases(collections)

# collection_aliases.each do |collection_alias|

	field_info = get_field_info(cdm_url, collection_alias)
	labels_and_nicks = get_labels_and_nicks(field_info)
	collection_map = get_collection_map(labels_and_nicks, meta_map)

	collection_title = collection_titles.fetch(collection_alias)
	download_dir = "#{config['cdm']['download_dir']}/#{collection_title}_(#{collection_alias})"
	FileUtils::mkdir_p download_dir
	puts "\nDownloading Collection: #{download_dir}\n"
	object_count = 0

	items = get_items(cdm_url, collection_alias)

	items['records'].each do |record|

		file_name = "#{collection_alias}_#{record['pointer']}.xml"

		if record['filetype'] == "cpd" # download compound object

			puts "Downloading Compound Object: #{file_name}"

			object_info = get_item_info(cdm_url, collection_alias, record['pointer'])
			new_object_info = transform_item(object_info, collection_map)

			compound_object_info = get_compound_object_info(cdm_url, collection_alias, record['pointer'])
			compound_object_items = get_compound_object_items(compound_object_info)

			file = String.new
			new_object_info.each {|line| file += "#{line}\n" unless (line.include? "index.cpd") || (line.include? "<cdm:") }

			# add pages to structure section
			file += "<structure>\n"
			page_num = 0
			compound_object_items.each do |pointer|
				page_num += 1
				puts "... getting page #{pointer}"
				file += "\t<page cdm=\"#{pointer}\">\n"
				item_info = get_item_info(cdm_url, collection_alias, pointer)
				new_item_info = transform_item(item_info, collection_map)
				new_item_info.each {|line| file += "\t\t#{line}\n" unless line.include? "<cdm:" }
				file += "\t</page>\n"			
			end
			file += "</structure>\n"				

			File.open(download_dir + "/" + file_name, 'w') { |f| f.write(file) }
			puts "... #{page_num} Pages Downloaded\n"
			object_count += 1

		else # download single object

			item_info = get_item_info(cdm_url, collection_alias, record['pointer'])
			new_item_info = transform_item(item_info, collection_map)

			file = String.new
			new_item_info.each {|line| file += "#{line}\n" unless line.include? "<cdm:" }

			File.open(download_dir + "/" + file_name, 'w') { |f| f.write(file) }
			puts "Single Object Downloaded: #{file_name}\n"
			object_count += 1

		end
	end

	puts "\n-----------------------------"
	puts "Collection Download Complete: #{collection_title} (#{object_count})"
	puts "-----------------------------\n"
	collection_count += 1
	total_object_count += object_count

#end

puts "\nMetadata Download Complete"
puts "Total Collections: #{collection_count}"
puts "Total Objects: #{total_object_count}\n\n"
