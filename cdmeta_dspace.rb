require 'open-uri'
require 'fileutils'
require 'json'
require 'nokogiri'
# require 'om'
require 'yaml'
require './cdmeta_methods'

config = YAML::load_file(File.join(__dir__, 'config_dspace.yml'))

server = config['cdm']['server']
port = config['cdm']['port']
cdm_url = "http://#{server}:#{port}/dmwebservices/index.php?q="

meta_map_config = config['meta_map']
meta_map = meta_map_to_hash_dspace(meta_map_config)
collections_config = config['collections']
collection_titles = collections_to_hash(collections_config)

puts "\nDownloading Repository Metadata\n"
collection_count = 0
total_object_count = 0

### uncomment next two lines for all collections
# collections = get_collections(cdm_url)
# collection_aliases = get_collection_aliases(collections)

### array for limited number of collections
# p15195coll39 theodor de bry
# p15195coll11 scenes middle east
# earlytex early texas documents
# jmac jagdish mehra audio
# saeng houston saengerbund records
collection_aliases = ["p15195coll11", "p15195coll39"]


# loop through collections
collection_aliases.each do |collection_alias|

	# get the field information and map to dspace dc
	field_info = get_field_info(cdm_url, collection_alias)
	labels_and_nicks = get_labels_and_nicks(field_info)
	collection_map = get_collection_map(labels_and_nicks, meta_map)

	# create archive directory for download
	collection_title = collection_titles.fetch(collection_alias)
	download_dir = "#{config['cdm']['download_dir']}/#{collection_title}_(#{collection_alias})"
	FileUtils::mkdir_p download_dir
	puts "\nDownloading Collection: #{download_dir}\n"
	object_count = 0

	# get all objects in collection and loop through each one
	items = get_items(cdm_url, collection_alias)
	items['records'].each do |record|

		# create object directory and prepare metadata variables
		object_count += 1
		object_download_dir = "#{download_dir}/item_%04d" % object_count
		FileUtils::mkdir_p object_download_dir
		content_file = ""
		metadata_file = "<dublin_core>\n"

		if record['filetype'] == "cpd" # download compound object

			puts "Downloading Compound Object: #{record['pointer']}"

			# get the object metadata
			object_info = get_item_info(cdm_url, collection_alias, record['pointer'])
			new_object_info = transform_item_dspace(object_info, collection_map)

			# store the object metadata
			new_object_info.each {|line| metadata_file += "\t#{line}\n"}

			# get the items in the object and loop through each one
			compound_object_info = get_compound_object_info(cdm_url, collection_alias, record['pointer'])
			compound_object_items = get_compound_object_items(compound_object_info)
			table_of_contents = ""
			page_num = 0
			compound_object_items.each do |pointer|
				page_num += 1
				puts "... getting item #{pointer}"

				# get the item metadata
				item_info = get_item_info(cdm_url, collection_alias, pointer)
				new_item_info = transform_item_dspace(item_info, collection_map)

				# store the item title in the table of contents
				table_of_contents += "Image #{page_num}: " + item_info.fetch("title") + "\n" unless item_info.fetch("title").nil?

				# store item descriptions, captions, and inscriptions in object metadata
				new_item_info.each do |line|
					if line.include? "element=\"description"
						original_description = line.split(">")
						new_description = "#{original_description[0]}>(Image #{page_num}) #{original_description[1]}>"
						metadata_file += "\t#{new_description}\n"
					else
						next
					end
				end

				# add sequential number to file name and store in content file
				original_file_name = item_info.fetch("file").split(".")
				new_file_name = "#{original_file_name[0]}_%03d.#{original_file_name[1]}" % page_num
				content_file += new_file_name + "\n"
			end

			# store table of contents in metadata
			metadata_file += "\t<dcvalue element=\"description\" qualifier=\"tableofcontents\">#{table_of_contents.chomp}</dcvalue>\n"
			puts "... #{page_num} Items Downloaded\n"

		else # download single object

			# get the item information
			item_info = get_item_info(cdm_url, collection_alias, record['pointer'])
			new_item_info = transform_item_dspace(item_info, collection_map)

			# store the item metadata
			new_item_info.each {|line| metadata_file += "\t#{line}\n"}

			# store file name in content file
			original_file_name = item_info.fetch("file").split(".")
			new_file_name = "#{original_file_name[0]}_001.#{original_file_name[1]}"
			content_file += new_file_name + "\n"			

			puts "Single Object Downloaded: #{record['pointer']}\n"
		end

		# write the metadata and content files
		metadata_file += "</dublin_core>"
		File.open(object_download_dir + "/contents", 'w') { |f| f.write(content_file.chomp) }
		File.open(object_download_dir + "/dublin_core.xml", 'w') { |f| f.write(metadata_file) }
	end

	puts "\n-----------------------------"
	puts "Collection Download Complete: #{collection_title} (#{object_count})"
	puts "-----------------------------\n"
	collection_count += 1
	total_object_count += object_count

end

puts "\nMetadata Download Complete"
puts "Total Collections: #{collection_count}"
puts "Total Objects: #{total_object_count}\n\n"
