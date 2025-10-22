const std = @import("std");
const curl = @import("curl");


pub fn fetch_file(url: [:0]const u8, file: *std.fs.File) !void {
    const alc = std.heap.page_allocator;

    const ca_bundle = try curl.allocCABundle(alc);
    defer ca_bundle.deinit();
    var easy = try curl.Easy.init(.{
        .ca_bundle = ca_bundle,
    });
    defer easy.deinit();

    try easy.setUrl(url);
    try easy.setWritefunction(writeCallback);
    try easy.setWritedata(file);

    _ = try easy.perform();
    
}

fn writeCallback(data: [*c]c_char, size: c_uint, nmemb: c_uint, user_data: *anyopaque) callconv(.c) c_uint {
    const real_size = @as(usize, size) * @as(usize, nmemb);
    const file = @as(*std.fs.File, @ptrCast(@alignCast(user_data)));
    _ = file.write(@as([*]const u8, @ptrCast(data))[0..real_size]) catch return 0;
    return @intCast(real_size);
}
