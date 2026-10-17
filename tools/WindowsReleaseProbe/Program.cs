using System.Buffers.Binary;
using System.IO.Compression;
using System.Reflection.PortableExecutable;
using System.Security.Cryptography;
using System.Text.Json;
using System.Xml.Linq;

// Reads the actual PE resources, not ExtractAssociatedIcon's single cached shell size.
// No application/installer is executed by this verifier; installation is a separate gate.
internal static class Program
{
    private static readonly int[] RequiredSizes = [16, 20, 24, 32, 40, 48, 64, 128, 256];
    private const string LegacyIconSha256 = "924c99ca9a3de54dbc722a4f0506664e8e115e005433dc522eaaddce669a8415";
    private static readonly List<object> Results = [];
    private static bool _rejectionFixtureChecked;

    private static int Main(string[] args)
    {
        try
        {
            var options = ParseOptions(args);
            var root = Path.GetFullPath(Required(options, "source-root"));
            var output = Path.GetFullPath(Required(options, "output"));
            Directory.CreateDirectory(output);
            if (options.TryGetValue("legacy-installed-root", out var legacyRoot))
            {
                var legacyIcon = File.ReadAllBytes(Required(options, "legacy-icon"));
                Require(Sha(legacyIcon) == LegacyIconSha256, "The upgrade baseline ICO is not the public 0.9.6 logo.");
                var legacyFrames = ReadIco(legacyIcon);
                Require(legacyFrames.Select(frame => frame.Size).SequenceEqual(RequiredSizes), "The legacy upgrade baseline is missing a required icon frame.");
                foreach (var relative in new[] { "dejavu.exe", "Update.exe", "current/dejavu.exe" })
                    VerifyPe("legacy-installed/" + relative, File.ReadAllBytes(Path.Combine(legacyRoot, relative)), legacyFrames, testRejection: false);
                File.WriteAllText(Path.Combine(output, "legacy-upgrade-precondition.json"), JsonSerializer.Serialize(new
                {
                    schemaVersion = 1, success = true, baselineVersion = "0.9.6", legacyIconSha256 = LegacyIconSha256,
                    scope = "All three actually installed 0.9.6 executables contain every old logo frame before upgrade", checks = Results
                }, new JsonSerializerOptions { WriteIndented = true }));
                Console.WriteLine("Windows upgrade baseline: 3 actual installed executables match every public 0.9.6 legacy logo frame.");
                return 0;
            }
            options.TryGetValue("generated-assets", out var generatedAssets);
            if (generatedAssets is not null && new[] { "release-dir", "publish-dir", "installed-root" }.Any(options.ContainsKey))
                throw new ArgumentException("A generator smoke output must not be substituted for packaged release assets.");
            var expected = VerifySource(root, output, generatedAssets);
            var version = XDocument.Load(Path.Combine(root, "ClaudeUsageTray.csproj"))
                .Descendants("Version").Single().Value;
            if (options.TryGetValue("version", out var requested) && requested != version)
                throw new InvalidDataException("Release version does not match the source project.");
            if (options.TryGetValue("publish-dir", out var publish))
                VerifyPe(Path.Combine(publish, "dejavu.exe"), File.ReadAllBytes(Path.Combine(publish, "dejavu.exe")), expected);
            if (options.TryGetValue("release-dir", out var release)) VerifyRelease(release, version, expected);
            if (options.TryGetValue("installed-root", out var installed))
            {
                foreach (var relative in new[] { "dejavu.exe", "Update.exe", "current/dejavu.exe" })
                {
                    var path = Path.Combine(installed, relative);
                    VerifyPe("installed/" + relative, File.ReadAllBytes(path), expected);
                }
            }
            var report = new { schemaVersion = 1, version, success = true,
                checkedAtUtc = DateTimeOffset.UtcNow, scope = "Source provenance and every Windows ICO/PE icon frame; not physical-DPI acceptance", checks = Results };
            File.WriteAllText(Path.Combine(output, "windows-release-icons.json"), JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
            Console.WriteLine($"Windows release icon acceptance: {Results.Count} sources/artifacts, all {RequiredSizes.Length} frames matched, 0 failures");
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine("WINDOWS RELEASE ICON FAILURE: " + error.Message);
            return 1;
        }
    }

    private static Dictionary<string, string> ParseOptions(string[] args)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        for (var i = 0; i < args.Length; i += 2)
        {
            if (!args[i].StartsWith("--", StringComparison.Ordinal) || i + 1 >= args.Length)
                throw new ArgumentException("Expected --name value options.");
            result.Add(args[i][2..], args[i + 1]);
        }
        return result;
    }

    private static string Required(Dictionary<string, string> options, string name) =>
        options.TryGetValue(name, out var value) ? value : throw new ArgumentException("Missing --" + name);
    private static string Sha(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidDataException(message);
    }

    private static List<IconFrame> VerifySource(string root, string output, string? generatedAssets)
    {
        string Asset(string name) => generatedAssets is null ? Path.Combine(root, "assets", name) : Path.Combine(generatedAssets, name);
        foreach (var pair in new[] { ("brand-mark.svg", "brand-mark.svg"), ("brand-mark-mono.svg", "brand-exploration/frame-mono.svg") })
        {
            var production = File.ReadAllBytes(Path.Combine(root, "assets", pair.Item1));
            var approved = File.ReadAllBytes(Path.Combine(root, "design/prototype", pair.Item2));
            Require(production.SequenceEqual(approved), pair.Item1 + " differs from the approved design reference.");
            Results.Add(new { kind = "approved-svg-provenance", name = pair.Item1, sha256 = Sha(production) });
        }
        var icon = File.ReadAllBytes(Asset("dejavu.ico"));
        Require(Sha(icon) != LegacyIconSha256, "The legacy blue dejavu.ico must never be released again.");
        var expected = ReadIco(icon);
        Require(expected.Select(frame => frame.Size).SequenceEqual(RequiredSizes), "Application ICO is missing an expected DPI frame or includes an unexpected frame.");
        foreach (var frame in expected)
        {
            Require(frame.Planes == 1 && frame.BitCount == 32, "ICO frame is not a 32-bit image.");
            Require(frame.Bytes.AsSpan().StartsWith(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }), "ICO frame is not a PNG image.");
            Require(BinaryPrimitives.ReadInt32BigEndian(frame.Bytes.AsSpan(16)) == frame.Size && BinaryPrimitives.ReadInt32BigEndian(frame.Bytes.AsSpan(20)) == frame.Size,
                "ICO PNG dimensions differ from its directory.");
            File.WriteAllBytes(Path.Combine(output, $"approved-app-{frame.Size}.png"), frame.Bytes);
        }
        Results.Add(new { kind = "application-ico", name = "assets/dejavu.ico", sha256 = Sha(icon), frames = expected.Select(frame => new { frame.Size, pngSha256 = Sha(frame.Bytes) }) });
        using var manifest = JsonDocument.Parse(File.ReadAllText(Asset("brand-icons.json")));
        Require(manifest.RootElement.GetProperty("schemaVersion").GetInt32() == 1, "Unsupported brand provenance manifest.");
        Require(manifest.RootElement.GetProperty("sizes").EnumerateArray().Select(value => value.GetInt32()).SequenceEqual(RequiredSizes), "Brand manifest sizes do not match the Windows DPI contract.");
        foreach (var source in manifest.RootElement.GetProperty("sources").EnumerateArray())
        {
            var sourceBytes = File.ReadAllBytes(Path.Combine(root, source.GetProperty("path").GetString()!));
            var approvedBytes = File.ReadAllBytes(Path.Combine(root, source.GetProperty("approvedReference").GetString()!));
            Require(Sha(sourceBytes) == source.GetProperty("sha256").GetString() && Sha(approvedBytes) == source.GetProperty("approvedSha256").GetString()
                && sourceBytes.SequenceEqual(approvedBytes), "Brand source provenance manifest is stale or inconsistent.");
        }
        var manifestIcons = manifest.RootElement.GetProperty("icons").EnumerateArray().ToList();
        Require(manifestIcons.Select(value => value.GetProperty("path").GetString()).Order().SequenceEqual(
            new[] { "assets/dejavu.ico", "assets/dejavu-tray-dark.ico", "assets/dejavu-tray-light.ico" }.Order()), "Brand manifest must cover the app and both taskbar contrast variants.");
        foreach (var item in manifestIcons)
        {
            var name = item.GetProperty("path").GetString()!;
            var data = File.ReadAllBytes(Asset(Path.GetFileName(name)));
            var frames = ReadIco(data);
            var recorded = item.GetProperty("frames").EnumerateArray().ToList();
            Require(Sha(data) == item.GetProperty("sha256").GetString() && frames.Count == RequiredSizes.Length && frames.Count == recorded.Count,
                name + " does not match the generated brand manifest.");
            for (var index = 0; index < frames.Count; index++)
            {
                Require(frames[index].Size == RequiredSizes[index] && recorded[index].GetProperty("size").GetInt32() == frames[index].Size
                    && recorded[index].GetProperty("sha256").GetString() == Sha(frames[index].Bytes), name + " contains an unrecorded or stale raster frame.");
                File.WriteAllBytes(Path.Combine(output, Path.GetFileNameWithoutExtension(name) + $"-{frames[index].Size}.png"), frames[index].Bytes);
            }
            // This independent pixel check prevents a self-consistent but legacy ICO
            // and manifest from being called the approved SVG-derived brand.
            foreach (var frame in frames.Where(frame => frame.Size is 64 or 256))
            {
                var pixels = ReadRgbaPng(frame.Bytes, frame.Size);
                var palette = name switch
                {
                    "assets/dejavu.ico" => new uint[] { 0xdde2d2ff, 0x203e2eff, 0x97a789ff },
                    "assets/dejavu-tray-dark.ico" => new uint[] { 0x171c17ff },
                    _ => new uint[] { 0xffffffff }
                };
                Require(palette.All(color => pixels.Contains(color)), name + " does not contain the approved opaque brand palette.");
                Require(pixels.Any(color => (color & 0xff) == 0), name + " has lost its transparent background.");
            }
            Results.Add(new { kind = "brand-generated-provenance", name, sha256 = Sha(data), frames = frames.Select(frame => frame.Size) });
        }
        return expected;
    }

    private static uint[] ReadRgbaPng(byte[] png, int size)
    {
        Require(png[24] == 8 && png[25] == 6 && png[28] == 0, "Brand PNG must be non-interlaced 8-bit RGBA.");
        using var compressed = new MemoryStream();
        for (var at = 8; at < png.Length;)
        {
            var length = checked((int)BinaryPrimitives.ReadUInt32BigEndian(png.AsSpan(at, 4)));
            var kind = System.Text.Encoding.ASCII.GetString(png, at + 4, 4);
            if (kind == "IDAT") compressed.Write(png, at + 8, length);
            at = checked(at + 12 + length);
        }
        compressed.Position = 0;
        using var zlib = new ZLibStream(compressed, CompressionMode.Decompress);
        var rows = new byte[checked(size * (1 + 4 * size))];
        zlib.ReadExactly(rows);
        Require(zlib.ReadByte() == -1, "Brand PNG contains unexpected decompressed image data.");
        var stride = 4 * size;
        var decoded = new byte[size * stride];
        for (var y = 0; y < size; y++)
        {
            var filter = rows[y * (stride + 1)];
            Require(filter <= 4, "Brand PNG uses an invalid filter.");
            for (var x = 0; x < stride; x++)
            {
                var left = x >= 4 ? decoded[y * stride + x - 4] : 0;
                var above = y > 0 ? decoded[(y - 1) * stride + x] : 0;
                var corner = x >= 4 && y > 0 ? decoded[(y - 1) * stride + x - 4] : 0;
                var predicted = filter switch { 0 => 0, 1 => left, 2 => above, 3 => (left + above) / 2, _ => Paeth(left, above, corner) };
                decoded[y * stride + x] = unchecked((byte)(rows[y * (stride + 1) + 1 + x] + predicted));
            }
        }
        return Enumerable.Range(0, size * size).Select(index => BinaryPrimitives.ReadUInt32BigEndian(decoded.AsSpan(index * 4, 4))).ToArray();
    }

    private static int Paeth(int left, int above, int corner)
    {
        var estimate = left + above - corner;
        var a = Math.Abs(estimate - left); var b = Math.Abs(estimate - above); var c = Math.Abs(estimate - corner);
        return a <= b && a <= c ? left : b <= c ? above : corner;
    }

    private static void VerifyRelease(string directory, string version, List<IconFrame> expected)
    {
        var versioned = File.ReadAllBytes(Path.Combine(directory, "dejavu-desktop-win-Setup.exe"));
        var stable = File.ReadAllBytes(Path.Combine(directory, "dejavu-Setup.exe"));
        Require(versioned.SequenceEqual(stable), "Stable Setup alias differs from the versioned Setup.");
        VerifyPe("dejavu-desktop-win-Setup.exe", versioned, expected);
        VerifyPe("dejavu-Setup.exe", stable, expected);
        using (var package = ZipFile.OpenRead(Path.Combine(directory, $"dejavu-desktop-{version}-full.nupkg")))
        {
            var setupIcon = ReadEntry(package, "setup.ico");
            Require(ReadIco(setupIcon).Zip(expected).All(pair => SameFrame(pair.First, pair.Second)) && ReadIco(setupIcon).Count == expected.Count,
                "The nupkg setup.ico does not contain the approved frames.");
            Results.Add(new { kind = "nupkg-setup-ico", name = "setup.ico", sha256 = Sha(setupIcon) });
            var nuspec = XDocument.Parse(System.Text.Encoding.UTF8.GetString(ReadEntry(package, "dejavu-desktop.nuspec")));
            Require(nuspec.Descendants().Single(element => element.Name.LocalName == "version").Value == version, "nupkg version does not match the release.");
            foreach (var name in new[] { "lib/app/dejavu.exe", "lib/app/dejavu_ExecutionStub.exe", "lib/app/Squirrel.exe" })
                VerifyPe("nupkg/" + name, ReadEntry(package, name), expected);
        }
        using var portable = ZipFile.OpenRead(Path.Combine(directory, "dejavu-desktop-win-Portable.zip"));
        foreach (var name in new[] { "dejavu.exe", "Update.exe", "current/dejavu.exe" })
            VerifyPe("portable/" + name, ReadEntry(portable, name), expected);
    }

    private static byte[] ReadEntry(ZipArchive zip, string name)
    {
        var entry = zip.GetEntry(name) ?? throw new InvalidDataException("Missing archive entry " + name);
        using var source = entry.Open();
        using var target = new MemoryStream();
        source.CopyTo(target);
        return target.ToArray();
    }

    private static bool SameFrame(IconFrame first, IconFrame second) =>
        first.Size == second.Size && first.Planes == second.Planes && first.BitCount == second.BitCount && first.Bytes.SequenceEqual(second.Bytes);

    private static List<IconFrame> ReadIco(byte[] bytes)
    {
        Require(U16(bytes, 0) == 0 && U16(bytes, 2) == 1, "Invalid ICO header.");
        var count = U16(bytes, 4);
        var frames = new List<IconFrame>();
        for (var i = 0; i < count; i++)
        {
            var at = 6 + 16 * i;
            var width = bytes[at] == 0 ? 256 : bytes[at];
            var height = bytes[at + 1] == 0 ? 256 : bytes[at + 1];
            Require(width == height, "Non-square ICO frame.");
            frames.Add(new IconFrame(width, U16(bytes, at + 4), U16(bytes, at + 6), bytes.AsSpan(checked((int)U32(bytes, at + 12)), checked((int)U32(bytes, at + 8))).ToArray()));
        }
        return frames.OrderBy(frame => frame.Size).ToList();
    }

    private static void VerifyPe(string name, byte[] bytes, List<IconFrame> expected, bool testRejection = true)
    {
        using var stream = new MemoryStream(bytes, writable: false);
        using var reader = new PEReader(stream);
        var headers = reader.PEHeaders;
        var directory = headers.PEHeader?.ResourceTableDirectory ?? throw new InvalidDataException(name + " is not a PE executable.");
        int Rva(int value)
        {
            foreach (var section in headers.SectionHeaders)
                if (value >= section.VirtualAddress && value < section.VirtualAddress + Math.Max(section.VirtualSize, section.SizeOfRawData))
                    return checked(section.PointerToRawData + value - section.VirtualAddress);
            throw new InvalidDataException(name + " contains an unmapped resource address.");
        }
        var resourceBase = Rva(directory.RelativeVirtualAddress);
        var leaves = new List<Resource>();
        void Walk(int relative, List<uint> path)
        {
            Require(path.Count <= 3, name + " contains an invalid resource tree.");
            var at = checked(resourceBase + relative);
            var count = U16(bytes, at + 12) + U16(bytes, at + 14);
            for (var i = 0; i < count; i++)
            {
                var entry = at + 16 + i * 8;
                var key = U32(bytes, entry);
                var child = U32(bytes, entry + 4);
                var next = path.Append(key).ToList();
                if ((child & 0x80000000) != 0) Walk(checked((int)(child & 0x7fffffff)), next);
                else
                {
                    var leaf = checked(resourceBase + (int)child);
                    var offset = Rva(checked((int)U32(bytes, leaf)));
                    leaves.Add(new Resource(next, bytes.AsSpan(offset, checked((int)U32(bytes, leaf + 4))).ToArray()));
                }
            }
        }
        Walk(0, []);
        var groups = leaves.Where(resource => resource.Path[0] == 14).ToList();
        Require(groups.Count > 0, name + " has no RT_GROUP_ICON.");
        var used = new HashSet<Resource>();
        foreach (var group in groups)
        {
            Require(U16(group.Bytes, 0) == 0 && U16(group.Bytes, 2) == 1 && U16(group.Bytes, 4) == expected.Count, name + " has an incomplete or unexpected icon group.");
            var frames = new List<IconFrame>();
            for (var i = 0; i < expected.Count; i++)
            {
                var at = 6 + 14 * i;
                var size = group.Bytes[at] == 0 ? 256 : group.Bytes[at];
                var height = group.Bytes[at + 1] == 0 ? 256 : group.Bytes[at + 1];
                Require(size == height, name + " has a non-square icon group frame.");
                var id = U16(group.Bytes, at + 12);
                var candidates = leaves.Where(resource => resource.Path[0] == 3 && resource.Path[1] == id).ToList();
                var image = candidates.SingleOrDefault(resource => resource.Path[2] == group.Path[2]) ?? (candidates.Count == 1 ? candidates[0] : null);
                Require(image is not null, name + " is missing the RT_ICON referenced by its group.");
                var resource = image!;
                Require(resource.Bytes.Length == U32(group.Bytes, at + 8), name + " has an icon resource length mismatch.");
                used.Add(resource);
                frames.Add(new IconFrame(size, U16(group.Bytes, at + 4), U16(group.Bytes, at + 6), resource.Bytes));
            }
            Require(frames.OrderBy(frame => frame.Size).Zip(expected).All(pair => SameFrame(pair.First, pair.Second)), name + " embeds an old or altered logo frame.");
        }
        Require(leaves.Count(resource => resource.Path[0] == 3) == used.Count, name + " contains unreferenced icon resources, which may retain a stale logo.");
        Results.Add(new { kind = "pe-all-icon-groups", name, sha256 = Sha(bytes), groups = groups.Count, frames = expected.Select(frame => frame.Size) });
        if (testRejection && !_rejectionFixtureChecked)
        {
            // A green report must also prove the verifier rejects a changed embedded
            // frame. Only an in-memory fixture is modified; release files are untouched.
            var changed = bytes.ToArray();
            var imageOffset = changed.AsSpan().IndexOf(expected[0].Bytes);
            Require(imageOffset >= 0, "Could not construct the icon-rejection regression fixture.");
            changed[imageOffset + 24] ^= 1;
            var rejected = false;
            try { VerifyPe("negative altered-icon fixture", changed, expected, testRejection: false); }
            catch (InvalidDataException) { rejected = true; }
            Require(rejected, "The release verifier accepted a changed embedded icon frame.");
            _rejectionFixtureChecked = true;
            Results.Add(new { kind = "negative-fixture", name = "altered embedded PNG frame", rejected = true });
        }
    }

    private static ushort U16(byte[] bytes, int offset) => BinaryPrimitives.ReadUInt16LittleEndian(bytes.AsSpan(offset, 2));
    private static uint U32(byte[] bytes, int offset) => BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(offset, 4));
    private sealed record IconFrame(int Size, ushort Planes, ushort BitCount, byte[] Bytes);
    private sealed record Resource(List<uint> Path, byte[] Bytes);
}
