const std = @import("std");
const curl = @import("curl");

pub fn fetch_file(url: [:0]const u8, file: std.fs.File) !void {
    const alc = std.heap.page_allocator;

    const ca_bundle = try curl.allocCABundle(alc);
    defer ca_bundle.deinit();
    const easy = try curl.Easy.init(.{
        .ca_bundle = ca_bundle,
    });
    defer easy.deinit();

    var buffer: [1024]u8 = undefined;

    var writer = std.Io.Writer.fixed(&buffer);
    const resp = try easy.fetch(url, .{ .writer = &writer });

    if (resp.status_code == 200) {
        try file.writeAll(writer.buffered());
    }
}
