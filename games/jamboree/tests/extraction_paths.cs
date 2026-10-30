using System;
using System.IO;

static class ExtractionPathTests {
    static int checks;
    static void Reject(Action action) {
        checks++;
        try { action(); } catch (IOException) { return; }
        throw new Exception("unsafe extraction path accepted");
    }
    public static int Main(string[] args) {
        string root = Path.Combine(args[0], "fixtures"), outside = Path.Combine(args[0], "outside");
        Directory.CreateDirectory(root); Directory.CreateDirectory(outside);
        foreach (string path in new[] { "nested/file.txt", "/nested/file.txt", "/日本語/file.txt" }) {
            string result = ExtractionPaths.Resolve(root, path);
            checks++;
            if (result != Path.Combine(root, path.TrimStart('/'))) throw new Exception("valid path changed");
        }
        foreach (string path in new[] { null, "", "/", ".", "..", "../escape", "/../../escape", "a/../escape",
                                       "a/./file", "a//file", "//escape", "a\\file", "C:/escape", "a\0file" })
            Reject(() => ExtractionPaths.Resolve(root, path));
        string sentinel = Path.Combine(outside, "sentinel.txt"); File.WriteAllText(sentinel, "preserve");
        Directory.CreateSymbolicLink(Path.Combine(root, "directory-link"), outside);
        File.CreateSymbolicLink(Path.Combine(root, "file-link"), sentinel);
        File.CreateSymbolicLink(Path.Combine(root, "dangling-link"), Path.Combine(outside, "absent"));
        Reject(() => ExtractionPaths.Resolve(root, "/directory-link/sentinel.txt"));
        Reject(() => ExtractionPaths.Resolve(root, "/file-link"));
        Reject(() => ExtractionPaths.Resolve(root, "/dangling-link"));
        Reject(() => ExtractionPaths.CheckRoot(Path.Combine(root, "directory-link")));
        Reject(() => ExtractionPaths.Resolve(Path.Combine(root, "directory-link", "new"), "file"));
        checks++;
        if (File.ReadAllText(sentinel) != "preserve" || File.Exists(Path.Combine(outside, "absent")))
            throw new Exception("outside sentinel changed");
        Console.WriteLine($"extraction paths: {checks} checks passed");
        return 0;
    }
}
