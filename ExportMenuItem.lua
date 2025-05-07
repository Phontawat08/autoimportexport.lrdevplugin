-- Access the Lightroom SDK namespaces.
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrBinding = import 'LrBinding'
local LrView = import 'LrView'
local LrApplication = import 'LrApplication'
local LrExportSession = import 'LrExportSession'
local LrTasks = import 'LrTasks'
local LrLogger = import 'LrLogger'
local myLogger = LrLogger('exportLogger')
myLogger:enable("print")

-- Function to check the operating system (Windows, MacOS, Linux)
local function getOS()
	local fh = io.popen("uname -s")
	local osname = fh and fh:read() or "Unknown"
	if fh then fh:close() end
	return osname == "Darwin" and "MacOS" or osname == "Linux" and "Linux" or "Windows"
end

local operatingSystem = getOS()

-- Function to process photos and save them as JPEG
local function processPhotos(photos, outputFolder, size, dpi, quality, format)
	LrFunctionContext.callWithContext("export", function(exportContext)
		local progressScope = LrDialogs.showModalProgressDialog({
			title = "Auto applying presets",
			caption = "",
			cannotCancel = false,
			functionContext = exportContext
		})

		local maxWidth, maxHeight = nil, nil -- Default to original size
		if size == "1080px" then
			maxWidth, maxHeight = 1080, 1080
		elseif size == "2000px" then
			maxWidth, maxHeight = 2000, 2000
		elseif size == "3000px" then
			maxWidth, maxHeight = 3000, 3000
		elseif size == "Facebook" then
			maxWidth, maxHeight = 2048, 2048
		elseif size == "Instagram" then
			maxWidth, maxHeight = 1080, 1350
		elseif size == "Line" then
			maxWidth, maxHeight = 1080, 1920
		elseif size == "original" then
			maxWidth, maxHeight = nil, nil
		end

		local exportSettings = {
			LR_collisionHandling = "rename",
			LR_export_bitDepth = "8",
			LR_export_colorSpace = "sRGB",
			LR_export_destinationPathPrefix = outputFolder,
			LR_export_destinationType = "specificFolder",
			LR_export_useSubfolder = false,
			LR_format = format,
			LR_minimizeEmbeddedMetadata = true,
			LR_outputSharpeningOn = false,
			LR_reimportExportedPhoto = false,
			LR_renamingTokensOn = true,
			LR_size_doNotEnlarge = true,
			LR_size_resolution = dpi,
			LR_size_units = "pixels",
			LR_tokens = "{{image_name}}",
			LR_useWatermark = false,
		}

		if format == "JPEG" then exportSettings.LR_jpeg_quality = quality end
		if maxWidth then
			exportSettings.LR_size_doConstrain = true
			exportSettings.LR_size_maxHeight = maxHeight
			exportSettings.LR_size_maxWidth = maxWidth
		else
			exportSettings.LR_size_doConstrain = false
		end

		local exportSession = LrExportSession({ photosToExport = photos, exportSettings = exportSettings })
		local numPhotos = exportSession:countRenditions()

		for i, rendition in exportSession:renditions({ progressScope = progressScope, renderProgressPortion = 1, stopIfCanceled = true }) do
			if progressScope:isCanceled() then break end
			progressScope:setPortionComplete(i - 1, numPhotos)
			progressScope:setCaption("Processing " ..
				rendition.photo:getFormattedMetadata("fileName") .. " (" .. i .. "/" .. numPhotos .. ")")
			rendition:waitForRender()
		end

		LrDialogs.message("Export Completed", "All photos have been processed.", "info")
	end)
end

-- Function to get develop preset names from "User Presets" folder
local function getDevelopPresetNames()
	local presetNames = {}
	local presetFolders = LrApplication.developPresetFolders()

	if presetFolders then
		for _, folder in ipairs(presetFolders) do
			if folder:getName() == "User Presets" then
				local folderPresets = folder:getDevelopPresets()
				if folderPresets then
					for _, preset in ipairs(folderPresets) do
						table.insert(presetNames, preset:getName())
					end
				end
				break -- Assuming only one "User Presets" folder
			end
		end
	end
	return presetNames
end

-- Get preset names from "User Presets"
local presetNames = getDevelopPresetNames()

-- Function to import pictures from folder where the rating is not 2 stars
local function importFolder(LrCatalog, folder, outputFolder, selectedPresetName, size, dpi, quality, format)
	local function getPresetByName(name)
		local presetFolders = LrApplication.developPresetFolders()
		for _, folder in ipairs(presetFolders) do
			if folder:getName() == "User Presets" then
				local folderPresets = folder:getDevelopPresets()
				for _, preset in ipairs(folderPresets) do
					if preset:getName() == name then
						return preset
					end
				end
				break -- Assuming only one "User Presets" folder
			end
		end
		return nil
	end
	local params = {
		{ value = selectedPresetName, name = "preset",       message = "Please select a preset!" },
		{ value = folder,             name = "folder",       message = "Please select the picture folder!" },
		{ value = size,               name = "size",         message = "Please select the size of the image!" },
		{ value = dpi,                name = "dpi",          message = "Please select the DPI of the image!" },
		{ value = quality,            name = "quality",      message = "Please select the quality of the image!" },
		{ value = format,             name = "format",       message = "Please select the format of the image!" },
		{ value = outputFolder,       name = "outputFolder", message = "Please select a folder to save your images!" },
	}

	for _, param in ipairs(params) do
		if not param.value or param.value == "" or param.value == nil then
			LrDialogs.message(param.message, "Error", "warning")
			return
		end
	end

	LrTasks.startAsyncTask(function()
		local photos = folder:getPhotos()
		local export = {}
		local preset = getPresetByName(selectedPresetName) -- Get the preset object
		if not preset then
			LrDialogs.message("Preset not found!", "Error", "critical")
			return
		end
		for _, photo in ipairs(photos) do
			if photo:getRawMetadata("rating") ~= 2 then
				LrCatalog:withWriteAccessDo("Apply Preset", function(context)
					photo:applyDevelopPreset(preset)
					photo:setRawMetadata("rating", 2)
					table.insert(export, photo)
				end)
			end
		end

		if #export > 0 then processPhotos(export, outputFolder, size, dpi, quality, format) end
	end)
end

-- GUI specification
local function customPicker()
	LrFunctionContext.callWithContext("showCustomDialogWithObserver", function(context)
		local props = LrBinding.makePropertyTable(context)
		local f = LrView.osFactory()
		local operatingSystemValue = f:static_text { title = operatingSystem }

		local presetField = f:combo_box {
			items = presetNames,
			value = LrView.bind("selectedPreset"),
			bind_to_object = props,
			immediate = true,
			onchange = function()
				if not props.selectedPreset or props.selectedPreset == "" then
					LrDialogs.message("Error", "Please select a preset before proceeding.", "critical")
					return
				end
			end
		}

		local outputFolderField = f:edit_field { immediate = true, width = 320, bind_to_object = props, value = LrView.bind("outputFolder") }

		local selectFolderButton = f:push_button {
			title = "Select Folder...",
			action = function()
				local result = LrDialogs.runOpenPanel { canChooseFiles = false, canChooseDirectories = true, allowsMultipleSelection = false }
				if result and #result > 0 then
					props.outputFolder = result[1]
					outputFolderField.title = result[1]
				end
			end
		}

		local outputFolderRow = f:row { spacing = 10, outputFolderField, selectFolderButton }
		local staticTextValue = f:static_text { title = "Not started" }

		-- Function to update the static text value
		local function myCalledFunction() staticTextValue.title = props.myObservedString end

		props:addObserver("myObservedString", myCalledFunction)

		LrTasks.startAsyncTask(function()
			local LrCatalog, catalogFolders = LrApplication.activeCatalog(), LrApplication.activeCatalog():getFolders()
			local folderCombo, folderIndex = {}, {}
			for i, folder in ipairs(catalogFolders) do
				folderCombo[i] = folder:getName(); folderIndex[folder:getName()] = i
			end

			local folderField = f:combo_box { items = folderCombo }
			local sizeField = f:combo_box { items = { "1080px", "2000px", "3000px", "Facebook", "Instagram", "Line", "original" }, value = "1080px" }
			local dpiField = f:combo_box { items = { "72", "300" }, value = "72" }
			local qualityField = f:combo_box { items = { "0.8", "0.85", "1" }, value = "0.8" }
			local formatField = f:combo_box { items = { "JPEG", "PNG" }, value = "JPEG" }
			local intervalField = f:combo_box { items = { "3", "5", "10" }, value = "3", width_in_digits = 3 }

			local watcherRunning = false

			-- Watcher, executes function and then sleeps x seconds using PowerShell
			local function watch(interval)
				LrTasks.startAsyncTask(function()
					while watcherRunning do
						LrDialogs.showBezel("Processing images.")
						importFolder(LrCatalog, catalogFolders[folderIndex[folderField.value]], outputFolderField.value,
							props.selectedPreset, sizeField.value, tonumber(dpiField.value), tonumber(qualityField.value),
							formatField.value)
						if LrTasks.canYield() then
							LrTasks.yield()
						end
						if operatingSystem == "Windows" then
							LrTasks.execute("powershell Start-Sleep -Seconds " .. interval)
						else
							LrTasks.execute("sleep " .. interval)
						end
					end
				end)
			end
			local c = f:column {
				spacing = f:dialog_spacing(),
				f:row { fill_horizontal = 1, f:static_text { alignment = "right", width = LrView.share "label_width", title = "Operating system: " }, operatingSystemValue },
				f:row { f:static_text { alignment = "right", width = LrView.share "label_width", title = "Select preset: " }, presetField },
				f:row { f:static_text { alignment = "right", width = LrView.share "label_width", title = "Select Lightroom Folder: " }, folderField },
				f:row { f:static_text { alignment = "right", width = LrView.share "label_width", title = "Size: " }, sizeField },
				f:row { f:static_text { alignment = "right", width = LrView.share "label_width", title = "DPI: " }, dpiField },
				f:row { f:static_text { alignment = "right", width = LrView.share "label_width", title = "Quality(JPEG): " }, qualityField },
				f:row { f:static_text { alignment = "right", width = LrView.share "label_width", title = "Format: " }, formatField },
				f:row { f:static_text { alignment = "right", width = LrView.share "label_width", title = "Interval (second): " }, intervalField },
				f:row { f:static_text { alignment = "right", width = LrView.share "label_width", title = "Output Folder: " }, outputFolderRow },
				f:row { f:separator { fill_horizontal = 1 } },
				f:row { fill_horizontal = 1, f:static_text { alignment = "right", width = LrView.share "label_width", title = "Watcher running: " }, staticTextValue },
				f:row {
					f:push_button {
						title = "Process once",
						action = function()
							if folderField.value ~= "" then
								props.myObservedString = "Processed once"
								importFolder(LrCatalog, catalogFolders[folderIndex[folderField.value]],
									outputFolderField.value, props.selectedPreset, sizeField.value,
									tonumber(dpiField.value), tonumber(qualityField.value), formatField.value)
							end
						end
					},
					f:push_button {
						title = "Watch interval",
						action = function()
							watcherRunning = true
							if folderField.value ~= "" then
								props.myObservedString = "Running"
								watch(intervalField.value)
							else
								LrDialogs.message("Please select an input folder")
							end
						end
					},
					f:push_button {
						title = "Pause watcher",
						action = function()
							watcherRunning = false
							props.myObservedString = "Stopped after running"
						end
					}
				},
			}

			LrDialogs.presentModalDialog { title = "Auto Export Images", contents = c }
		end)
	end)
end

customPicker()
