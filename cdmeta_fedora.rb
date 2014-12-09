require 'open-uri'
require 'fileutils'
require 'json'
require 'nokogiri'
require 'yaml'
require './cdmeta_methods'

admin_config = YAML::load_file(File.join(__dir__, 'config.yml'))
fedora_config = YAML::load_file(File.join(__dir__, 'config_fedora.yml'))

server = admin_config['cdm']['server']
port = admin_config['cdm']['port']
cdm_url = "http://#{server}:#{port}/dmwebservices/index.php?q="

meta_map_config = fedora_config['meta_map']
meta_map = meta_map_to_hash(meta_map_config)
collections_config = admin_config['collections']
collection_titles = collections_to_hash(collections_config)

puts "\nDownloading Repository Metadata\n"
collection_count = 0
total_object_count = 0

### EITHER uncomment next two lines for all collections
# collections = get_collections(cdm_url)
# collection_aliases = get_collection_aliases(collections)

### OR use array of aliases
# p15195coll39 (theodor de bry)
# p15195coll11 (scenes middle east)
# earlytex (early texas documents)
# jmac (jagdish mehra audio)
# saeng (houston saengerbund records)
collection_aliases = ["p15195coll39"]


# loop through collections
collection_aliases.each do |collection_alias|

	# get the field information and map to dc
	field_info = get_field_info(cdm_url, collection_alias)
	labels_and_nicks = get_labels_and_nicks(field_info)
	collection_map = get_collection_map(labels_and_nicks, meta_map)

	# create archive directory for download
	collection_title = collection_titles.fetch(collection_alias)
	download_dir = "#{admin_config['cdm']['download_dir']}/#{collection_title}_(#{collection_alias})"
	FileUtils::mkdir_p download_dir
	puts "\nDownloading Collection: #{download_dir}\n"
	object_count = 0

	# get all objects in collection and loop through each one
	items = get_items(cdm_url, collection_alias)
	items['records'].each do |record|

		object_count += 1

		dc_datastream_file = "\t\t\t\t<oai_dc:dc xmlns:oai_dc=\"http://www.openarchives.org/OAI/2.0/oai_dc/\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\">\n"

		if record['filetype'] == "cpd" # download compound object

			puts "Downloading Compound Object: #{record['pointer']}"

			# create object directory and prepare metadata variables
			object_download_dir = "#{download_dir}/item_%04d" % object_count
			FileUtils::mkdir_p object_download_dir
			content_file = ""

			# get the object metadata
			object_info = get_item_info(cdm_url, collection_alias, record['pointer'])
			new_object_info = transform_item_dspace(object_info, collection_map)

			# store the object metadata
			new_object_info.each {|line| dc_datastream_file += "\t#{line}\n"}

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
						dc_datastream_file += "\t#{new_description}\n"
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
			dc_datastream_file += "\t<dcvalue element=\"description\" qualifier=\"tableofcontents\">#{table_of_contents.chomp}</dcvalue>\n"
			puts "... #{page_num} Items Downloaded\n"

		else # download single object

			# get the item information
			item_info = get_item_info(cdm_url, collection_alias, record['pointer'])
			new_item_info = transform_item_fedora(item_info, collection_map)

			# store the item metadata
			new_item_info.each {|line| dc_datastream_file += "\t\t\t\t\t#{line}\n"}

			# store file name in content file
#			original_file_name = item_info.fetch("file").split(".")
#			new_file_name = "#{original_file_name[0]}_001.#{original_file_name[1]}"
#			content_file += new_file_name + "\n"			

			puts "Single Object Downloaded: #{record['pointer']}\n"
		end

		dc_datastream_file += "\t\t\t\t</oai_dc:dc>\n"

		object_name = item_info.fetch("title")

		foxml_file = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
		foxml_file += "<foxml:digitalObject xmlns:foxml=\"info:fedora/fedora-system:def/foxml#\" VERSION=\"1.1\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:schemaLocation=\"info:fedora/fedora-system:def/foxml# http://www.fedora.info/definitions/1/0/foxml1-1.xsd\">\n"
		foxml_file += "\t<foxml:objectProperties>\n"
		foxml_file += "\t\t<foxml:property NAME=\"info:fedora/fedora-system:def/model#state\" VALUE=\"A\"/>\n"
		foxml_file += "\t\t<foxml:property NAME=\"info:fedora/fedora-system:def/model#label\" VALUE=\"#{object_name}\"/>\n"
		foxml_file += "\t</foxml:objectProperties>\n"

		foxml_file += "\t<foxml:datastream ID=\"DC\" STATE=\"A\" CONTROL_GROUP=\"X\">\n"
		foxml_file += "\t\t<foxml:datastreamVersion FORMAT_URI=\"http://www.openarchives.org/OAI/2.0/oai_dc/\" ID=\"DC.0\" MIMETYPE=\"text/xml\" LABEL=\"Dublin Core Record\">\n"
		foxml_file += "\t\t\t<foxml:xmlContent>\n"

		foxml_file += dc_datastream_file

		foxml_file += "\t\t\t</foxml:xmlContent>\n"
		foxml_file += "\t\t</foxml:datastreamVersion>\n"
		foxml_file += "\t</foxml:datastream>\n"
		foxml_file += "</foxml:digitalObject>"

#		File.open(object_download_dir + "/contents", 'w') { |f| f.write(content_file.chomp) }
		File.open(download_dir + "/#{collection_alias}_#{record['pointer']}.xml", 'w') { |f| f.write(foxml_file) }
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
