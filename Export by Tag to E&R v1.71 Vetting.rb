######################################################################################
# ///// Nuix Interpreted Comments BEGIN
# Needs Case: true
# Menu Title: Export by Tag to E&R v1.7 (vetting version)
# encoding: utf-8
# ///// Nuix Interpreted Comments END
# Uses Nx.jar: https://github.com/Nuix/Nx
# UI and UI error logic taken from the Tag Nuker script: https://github.com/Nuix/Nukers
# Export to E&R Code from Export to E&R v 3A6
# Author: Nicholas COTTON
# Export to E&R by Tag
# 2020-02-24
# Changelog: 
# Changed spreadsheet/native export option to ensure it does on or the other but not both
# Fixed true false logic using checlist boolean variables
# Added logic for which options must be used together.
# Changed to only report material children, put some csv items into ""
# Combined markup into main panel to avoid confusion.
# Script will now write your TA for you, although you must still double check it's correct. 
# Commented out code for selecting a subset of markups, as I couldn't figure out how to sort them out.
# 2020-06-23
# 1.71 adds logic to check to for Nuix license features and does not attempt to offer vettting related options when not supported.
######################################################################################

script_directory = File.dirname(__FILE__)
require File.join(script_directory,"Nx.jar")
java_import "com.nuix.nx.NuixConnection"
java_import "com.nuix.nx.LookAndFeelHelper"
java_import "com.nuix.nx.dialogs.ChoiceDialog"
java_import "com.nuix.nx.dialogs.TabbedCustomDialog"
java_import "com.nuix.nx.dialogs.CommonDialogs"
java_import "com.nuix.nx.dialogs.ProgressDialog"
java_import "com.nuix.nx.dialogs.ProcessingStatusDialog"
java_import "com.nuix.nx.digest.DigestHelper"
java_import "com.nuix.nx.controls.models.Choice"

LookAndFeelHelper.setWindowsIfMetal
NuixConnection.setUtilities($utilities)
NuixConnection.setCurrentNuixVersion(NUIX_VERSION)

require 'csv' # For the export inventory file
require 'time' # For sanity checking timezone issues in the export inventory file
require "fileutils" # For moving PDFs around and renaming vetted files with the r in front.
require 'set'  # Used for sorting which markup is in use against which markup we want to actually use.
pdf_exporter = $utilities.getPdfPrintExporter() #For the non-vetted export
native_exporter = $utilities.getBinaryExporter  #For exporting native items
item_sorter = $utilities.getItemSorter() #Depreciated in Nuix 8.0, on the to-do list to use the new call, but for now it still works.
current_licence = $utilities.getLicence 	# Enable license feature checks	
bulk_annotater = $utilities.getBulkAnnotater # For applying a tag to everything that got exported.
export_metadata = "ExportID" 				#Custom Metadata for use with E&R
export_repeats = "ExportID-Duplicates"		#Custom Metadata to store previous ExportIDs. 	
evidence_source = $current_case.name		#For a better then nothing value in the "source" column on the exprot inventory file. 									

# Instructions Popup Window
javax.swing.JOptionPane.showMessageDialog(nil, "Instructions:
1. Select the single tag for the items you wish to export. 
2. Choose Export Options (PDFs, spreadsheets, other native files.)
3. Create/Choose a new empty export directory.
4. Entere a new unique T#_TA# for your export.
5. Change Source/RE/Type/Description values to match E&R task (if known).
6. Check desired vetting/redaction settings.
8. Hit Ok and Confirm. Script is not complete until you are notified by another pop-up.")

# Check to see if the script can run at all, code stolen from 
# https://github.com/Nuix/Export-Family-PDFs
if !current_licence.hasFeature("EXPORT_ITEMS") && !current_licence.hasFeature("EXPORT_LEGAL")
	CommonDialogs.showError("The current licence does not have features 'EXPORT_LEGAL' (needed to export production sets) or "+
		"'EXPORT_ITEMS' (needed to export selected items).  Please restart script with an appropriate licence.")
	exit 1
end


dialog = TabbedCustomDialog.new("Export Tagged Items to E&R")
#Have to calculate some values/layouts for the tags and markups. 
all_tags = $current_case.getAllTags.sort
tag_choices = all_tags.map{|t|Choice.new(t)}
markup_set_lookup = {}
if current_licence.hasFeature("EXPORT_LEGAL")
	$current_case.getMarkupSets.sort_by{|ms|ms.getName}.each{|ms| markup_set_lookup[ms.getName] = ms}
end
# Main setings Tab
#These all pretty much do what they say on the tin.
main_tab = dialog.addTab("settings_tab","Export Settings")
main_tab.appendChoiceTable("tag","Choose One Tag to Export:",tag_choices)
main_tab.appendCheckBox("export_report","Save CSV Report.",true)
main_tab.appendCheckBox("write_ta","Save autogenerated summary task action text",true)
main_tab.appendCheckBox("export_pdfs","Save PDF copies.",true)
main_tab.appendCheckBox("export_spreadsheets","Export native items of spreadsheet files [note: requires available binaries, check with DFS before using].",false)
main_tab.appendCheckBox("export_natives","Export native items for all other files [note: requires available binaries, check with DFS before using].",false)
main_tab.appendDirectoryChooser("export_directory","Export Directory:")
main_tab.appendTextField("task_taskaction","Task & Task Action numbers:","")
main_tab.appendTextField("report_author","Signature block for report author","Cst. XYZ 12345")
main_tab.appendTextField("evidence_source","\"Source\" for report CSV:","#{evidence_source}")
main_tab.appendTextField("evidence_RE","\"RE\" for report CSV","RE")
main_tab.appendTextField("evidence_TYPE","\"Document Type\" for report CSV","DOCUMENT TYPE")
main_tab.appendTextField("evidence_DESCRIPTION","\"Document Description\" for report CSV","DOCUMENT DESCRIPTION")
main_tab.appendCheckBox("export_markups","Export Markup (vetted) copies of PDFs [NOTE: Use only when license supports EXPORT-LEGAL (e.g. eDiscovery workstation) or the script will crash.]",false)
main_tab.appendCheckBox("apply_highlights","Apply Highlights",false)
main_tab.appendCheckBox("apply_redactions","Apply Redactions",false)
#main_tab.appendStringChoiceTable("markup_set_names","Markup Sets",markup_set_lookup.keys) # commented out until markup set selection is allowed.
# Controls which checkboxes are dependent on each other.
main_tab.enabledOnlyWhenChecked("evidence_RE","export_report") 
main_tab.enabledOnlyWhenChecked("evidence_TYPE","export_report")
main_tab.enabledOnlyWhenChecked("report_author","write_ta")
main_tab.enabledOnlyWhenChecked("evidence_DESCRIPTION","export_report")
main_tab.enabledOnlyWhenChecked("evidence_source","export_report")
main_tab.enabledOnlyWhenChecked("export_natives","export_spreadsheets")
if current_licence.hasFeature("EXPORT_LEGAL")
	main_tab.enabledOnlyWhenChecked("apply_highlights","export_markups")
	main_tab.enabledOnlyWhenChecked("apply_redactions","export_markups")
	#main_tab.enabledOnlyWhenChecked("markup_set_names","export_markups")  commented out until markup set selection is implemented.
end
# Worker settings, not sure I need it, but leaving it in for now, probably only effects the markup/vetted export.
worker_settings_tab = dialog.addTab("worker_settings_tab","Worker Settings")
worker_settings_tab.appendLocalWorkerSettings("worker_settings")


# Validate user settings against predicatable obvious errors. 
dialog.validateBeforeClosing do |values|
	# Make sure user selected at least one tag
	if values["tag"].size < 1 or values["tag"].size > 1
		CommonDialogs.showWarning("You must check one and only one tag.")
		next false
	end
	# Make sure user selected an export_directory
	if values["export_directory"].strip.empty?
		CommonDialogs.showWarning("You must select an export directory.")
		next false
	end
	# Make sure user provided a T/TA
	if values["task_taskaction"].strip.empty?
		CommonDialogs.showWarning("You must input Task & Task Action numbers.")
		next false
	end
	# Make sure user provided an evidence source
		if values["evidence_source"].strip.empty?
		CommonDialogs.showWarning("You must input the source of the evidence (default is the Nuix case name).")
		next false
	end
	# Make sure export options are logical
	if values["export_spreadsheets"] == false && values["export_natives"] == true then
		CommonDialogs.showWarning("If you wish to export both spreadsheets and all other natives click both boxes.")
		next false
	end
	# Get user to confirm that they are about to export some data
	message = "You are about export items from #{values["tag"]} tag. Proceed?"
	title = "Proceed?"
	next CommonDialogs.getConfirmation(message,title)
end

# Display the actual dialog
dialog.display

# If user clicked ok and settings checked out, lets get to work
if dialog.getDialogResult == true
	# Pull out settings from dialog into handy variables
	# These are all thing=values["thing"]
	values = dialog.toMap
	tag = values["tag"]
	export_pdfs = values["export_pdfs"]
	export_report = values["export_report"]
	export_spreadsheets = values["export_spreadsheets"]
	export_natives = values["export_natives"]
	export_directory = values["export_directory"]
	task_taskaction = values["task_taskaction"]
	temp_directory = values["export_directory"].gsub(/\\$/,"")+"\\#{task_taskaction}" # I know it's weird to use the tag again for the temp dir, but the production set inherits this name, so it just's cleaner. anyway we intend to delete it.
	evidence_source = values["evidence_source"]
	apply_redactions = values["apply_redactions"]
	apply_highlights = values["apply_highlights"]
	export_markups = values["export_markups"]
	worker_settings = values["worker_settings"]
#	markup_sets = values["markup_set_names"].map{|name| markup_set_lookup[name]} # This is how we would have done it if we were letting the user select a limited set of markup sets. 
	if current_licence.hasFeature("EXPORT_LEGAL")
		markup_sets = $current_case.getMarkupSets # This should force selecting all markup sets. 
	end
	evidence_RE = values["evidence_RE"]
	evidence_TYPE = values["evidence_TYPE"]
	evidence_DESCRIPTION = values["evidence_DESCRIPTION"]
	report_author = values["report_author"]
	write_ta = values["write_ta"]

### QA Interface design by printing variable values to console, although not all of them because eventually I knew what I was doing. 

	puts "Tag: #{tag.first}"
	puts "Markup: #{markup_sets}"
	puts "PDFS: #{export_pdfs}"
	puts "Report: #{export_report}"
	puts "Spreadsheets: #{export_spreadsheets}"
	puts "Natives: #{export_natives}"
	puts "Directory: #{export_directory}"
	puts "T-TA: #{task_taskaction}"
	puts "Evidence Source: #{evidence_source}" 
#	puts "Markup Sets Checked: #{markup_sets}"
	if current_licence.hasFeature("EXPORT_LEGAL")
		puts "Total markup sets: #{markup_set_lookup.keys}"
	end

## Phase 1
## This logic assigns the T/TA number metadata and subsequently exports 
	
search_items = $current_case.search("tag:\"#{tag.first}\"") 	      #.first becasue the single tag still gets passed as an array for some reason. 
export_items = item_sorter.sortItemsByTopLevelItemDate(search_items)  
export_items.each_with_index do |item,item_index| # Start Export Loop
	####Generate Unique ID in order of TopLevelItemDate 
	####(keeps emails and attachments together) starting from 0002
		base_number_string = (item_index+2)
		padded_number_string = base_number_string.to_s.rjust(5,"0")	
		### Determine the ID number		
		id_num = "#{task_taskaction}_#{padded_number_string}"				
		##### Enter or Updated ExportID custom metadata #
		# Get the item's custom metadata map
		item_custom_metadata = item.getCustomMetadata 
		# Get current ExportID value if present (checks for ? later)
		exportID_value = item_custom_metadata[export_metadata] 
		# Get current exportIDdup value if present (checks for nil later)
		previous_exportID_values = item_custom_metadata[export_repeats] 
		if exportID_value.nil?
			# If exportID is nil no complex thoughts areex required, as there are no duplicates to track.
			exportID_value = id_num	
		else
			# To backup ExportID to exportIDdup first check if exportIDdup already has a value.
			if previous_exportID_values.nil?	
				# If it's empty then put the old and new to start with both duplicates.
				previous_exportID_values = id_num + ", " + exportID_value 
			else
				#If it's NOT empty then ADD the new ID to the previous string. 
				previous_exportID_values = id_num + ", " + previous_exportID_values 
			end
			exportID_value = id_num
			item_custom_metadata[export_repeats] = previous_exportID_values
		end
		item_custom_metadata[export_metadata] = exportID_value
		#Determine the PDF file name.
		pdf_file_name = "#{id_num}.PDF" 	# Determine the PDF file name
		export_file_path = File.join(export_directory,pdf_file_name)		# File name + path
		#Optionally Export PDFs 																			
		if export_pdfs
			pdf_exporter.exportItem(item,export_file_path)
		end
		#Optionally export the native for spreadsheets or all natives (one way or the other, not both)	
		# This requires the evidence to be accessible to the case, or the binaries already to be populated in the case. 
		if export_spreadsheets  && !export_natives  then
			kind = "#{item.kind}"
			if kind == "spreadsheet" then
					extension = item.getOriginalExtension
				if extension.nil?
					extension = ".csv"
				end
				native_file_name = "#{id_num}.#{extension}"
				native_directory = File.join(export_directory,"Natives")
				java.io.File.new(native_directory).mkdirs
				native_export_file_path = File.join(native_directory,native_file_name)
				native_exporter.exportItem(item,native_export_file_path)
			end
			else if export_spreadsheets && export_natives then 
				extension = item.getOriginalExtension
				native_file_name = "#{task_taskaction}_#{padded_number_string}.#{extension}"
				native_directory = File.join(export_directory,"Natives")
				java.io.File.new(native_directory).mkdirs
				native_export_file_path = File.join(native_directory,native_file_name)
				native_exporter.exportItem(item,native_export_file_path)
			end
		end
		#End Native/Spreadsheet items export section.
		#Begin Tracking of ExportID on Duplicates of Exported item.
		duplicates = item.getDuplicates
		duplicates.each_with_index do |item,item_index|
			duplicates_custom_metadata = item.getCustomMetadata
			duplicate_exportID = item_custom_metadata[export_metadata]
			if previous_exportID_values.nil?
				duplicates_custom_metadata[export_metadata] = "Duplicate of #{exportID_value}"
			else 
				duplicates_custom_metadata[export_repeats] = "Duplicate of #{previous_exportID_values}"
			end
		end #End Tracking of ExportID on Duplicates of Exported Items section.
 
	# Create Item 001 inventory csv if requested.
	# Note, the first item will always be number 2, even if the CSV report #1 is not requested. I'm not going to change this becuase I think consistanty is less confusing, even when not totally logical. 
	if export_report then
		export_filename = "#{task_taskaction}_00001.csv"							
		report = File.join(export_directory,export_filename)						
		CSV.open(report, "w") do |writer|          									
			#Write header for CSV	
			writer << ["Filename/ExportID", "ExportID-Duplicates", "Vetting Codes", "Document Title", "RE", "Document Type", "Document Description", "Document Summary", "Source", "Document Date", "Document Time", "Original File Name", "Original File Type", "Evidence Path", "Attached or Embedded Items", "Nuix GUID", "Hash Values"]
			#Write contents for CSV based on each item.
			export_items.each_with_index do |item,item_index| # Runs script on as defined by original search way above. 
				exportid_forcsv = item.getCustomMetadata[export_metadata]
				exportiddup_forcsv = item.getCustomMetadata[export_repeats]
				t1 = Time.parse("#{item.date}") # needs to be tested against .nil?
				local_time = t1.getlocal
				csv_itemdate = local_time.strftime("%Y-%m-%d")
				csv_itemtime = local_time.strftime("%k:%M")
				child_items = item.getChildren
				material_children = child_items.select{|i|i.isAudited} # List of ONLY material items that are children of the given item. 
					if current_licence.hasFeature("EXPORT_LEGAL")
						writer << [exportid_forcsv, exportiddup_forcsv, item.getMarkupSets, item.name, "#{evidence_RE}", "#{evidence_TYPE}", "#{evidence_DESCRIPTION}", "#{item.comment}", evidence_source, csv_itemdate, csv_itemtime, item.name, "#{item.kind.getLocalisedName}", "#{item.getLocalisedPathNames}", "#{material_children}", "#{item.guid}", item.digests] 
					else
						writer << [exportid_forcsv, exportiddup_forcsv, "Vetting Not in Use", item.name, "#{evidence_RE}", "#{evidence_TYPE}", "#{evidence_DESCRIPTION}", "#{item.comment}", evidence_source, csv_itemdate, csv_itemtime, item.name, "#{item.kind.getLocalisedName}", "#{item.getLocalisedPathNames}", "#{material_children}", "#{item.guid}", item.digests]	
					end
				end
			end
		end
	end

	# Attempt legal export with stamped/vetted/redacted pdfs too, if requirested.
	# This has the side effect of creating a production set with a totally unrelated item number within Nuix. Recommend: ignore those or delete when done. 
	# This only works with the license feature EXPORT-LEGAL. 
	# Todo: Add a license check (sameple code on github in the export family PDFs) to abort pre-emptively if the license feature isn't present, right now it will probably just crash. 
	if current_licence.hasFeature("EXPORT_LEGAL")
		if export_markups then
			# Setup exporter for PDF export
			exporter = $utilities.createBatchExporter(temp_directory)
			exporter.setMarkupSets(markup_sets,{
				"applyRedactions" => values["apply_redactions"],
				"applyHighlights" => values["apply_highlights"],
			})
			# Configure it to use worker settings specified by user
			exporter.setParallelProcessingSettings(worker_settings)
			# Not surprisingly we need to export PDFs
			exporter.addProduct("pdf",{
				"naming" => "guid",
				"path" => "VettedPDFs",
				"regenerateStored" => "false",
			})
			exporter.exportItems(export_items)
			Dir.glob("#{temp_directory}/**/*.pdf").each do |pdf_file|
				guid = File.basename(pdf_file,".*")
				pdf_path = pdf_file.gsub("/","\\")
				vet_items = $current_case.search("guid:#{guid}")
				vet_items.each_with_index do |item,item_index| # Renaming looop. This will only keep items with markup/vetting and will delete everything else. 
					markup_inuse = item.getMarkupSets
					if markup_inuse.empty?
						puts "No vetted copy required: skipping item with guid:#{guid}"
						else
						item_custom_metadata = item.getCustomMetadata 
						# Get current ExportID value if present (checks for ? later)
						exportID_target = item_custom_metadata[export_metadata]
						exportID_target = "r" + exportID_target
						puts "Vetted copy required and created at: ExportID target name: #{exportID_target}"
						rpdf_file_name = "#{exportID_target}.PDF" 	# Determine the PDF file name
						rpdf_file_path = File.join(export_directory,rpdf_file_name)		# File name + path
						FileUtils.mv(pdf_file,rpdf_file_path)
					end
				end
		
			end
			org.apache.commons.io.FileUtils.deleteDirectory(java.io.File.new(temp_directory))
		end
	end
	# This section writes the TA text for use in E&R, using the input from the initial dialog and the computer's current time. 
	if write_ta then
	taskaction_file = "#{task_taskaction}.txt"
	taskaction_file = File.join(export_directory,taskaction_file)
	t2 = Time.now # needs to be tested against .nil?
	local_time = t2.getlocal
	report_date = local_time.strftime("%Y-%m-%d")
	report_time = local_time.strftime("%k:%M")
	count_items = $current_case.search("tag:\"#{tag.first}\"").count
	last_attachment = count_items + 1 # Since item 0001 is the spreadsheet.
	file = File.open(taskaction_file, "w") { |file| file.write("Nuix Export from Tag:\"#{tag.first}\" \n\nOn #{report_date} at #{report_time} hours, #{report_author} exported #{count_items} items from #{evidence_source} to E&R #{task_taskaction}. \n\n#{report_author}\n(NOTE: TA Text auto generated by E&R Export Script based on user input, verify accurancy then remove this note)\n\nAttachments\n01 #{evidence_DESCRIPTION}: INVENTORY SPREADSHEET \nInventory spreadsheet describing #{count_items} items exported from tag \"#{tag.first}\" to #{task_taskaction} on #{report_date}. Items are numbered from 2 to #{last_attachment}, this inventory spreadsheet is item 1. ") }
	end
bulk_annotater.addTag("Exported|#{task_taskaction}",export_items) # Adds tag tracking which items were exported in which dataset. Items can have multiple tags if exported multiple times.
end
javax.swing.JOptionPane.showMessageDialog(nil, "Scripts has completed.")