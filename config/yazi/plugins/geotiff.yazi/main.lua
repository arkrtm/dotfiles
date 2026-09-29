-- GeoTIFF プレビュー: geoview（uv + rasterio）で PNG に変換して表示する
-- 組み込みの magick プレビューアと同じ構成
local M = {}

function M:peek(job)
	local start, cache = os.clock(), ya.file_cache(job)
	if not cache then
		return
	end

	local ok, err = self:preload(job)
	if not ok or err then
		return ya.preview_widget(job, err)
	end

	ya.sleep(math.max(0, rt.preview.image_delay / 1000 + start - os.clock()))

	local _, err = ya.image_show(cache, job.area)
	ya.preview_widget(job, err)
end

function M:seek() end

function M:preload(job)
	local cache = ya.file_cache(job)
	if not cache or fs.cha(cache) then
		return true
	end

	local size = math.max(rt.preview.max_width, rt.preview.max_height)
	local output, err = Command("geoview")
		:arg({ tostring(job.file.path), "-o", tostring(cache), "--size", tostring(size) })
		:output()
	if not output then
		return true, Err("Failed to start `geoview`, error: %s", err)
	elseif not output.status.success then
		return false, Err("`geoview` failed: %s", output.stderr)
	end
	return true
end

return M
