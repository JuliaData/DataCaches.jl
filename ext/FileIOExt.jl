module FileIOExt

using DataCaches
using FileIO
using DataCaches: CacheSerializer, format_tag, file_extension, write_data, read_data,
                  register_serializer!

# One concrete serializer per image format.
for (Fmt, tag, ext) in (
        (:PNGSerializer, "png", ".png"),
        (:JPGSerializer, "jpg", ".jpg"),
        (:TIFSerializer, "tif", ".tif"),
    )
    @eval begin
        struct $Fmt <: CacheSerializer end
        DataCaches.format_tag(::$Fmt)                  = $tag
        DataCaches.file_extension(::$Fmt)              = $ext
        DataCaches.write_data(::$Fmt, fpath::String, data) = FileIO.save(fpath, data)
        DataCaches.read_data(::$Fmt, fpath::String)        = FileIO.load(fpath)
    end
end

function __init__()
    register_serializer!("png", PNGSerializer())
    register_serializer!("jpg", JPGSerializer())
    register_serializer!("tif", TIFSerializer())
end

# Note: write-side dispatch (serializer_for for image arrays such as
# Matrix{<:Colorant}) requires ColorTypes to be loaded and is provided
# by a separate ColorTypesExt extension. Without it, image arrays fall
# through to OpaqueSerializer. Users can always pass format="png" to
# write! to use image serialization explicitly.

end # module FileIOExt
