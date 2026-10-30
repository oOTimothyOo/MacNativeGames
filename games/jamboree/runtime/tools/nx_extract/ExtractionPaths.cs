using System;
using System.IO;

// Archive paths and host paths have different trust boundaries. LibHac's
// normalization does not prevent an existing host symlink redirecting a write.
static class ExtractionPaths {
    public static void CheckRoot(string root) => RejectLinks(Path.GetFullPath(root));

    public static string Resolve(string root, string entry) {
        if (string.IsNullOrEmpty(entry) || entry.IndexOfAny(new[] { '\0', '\\', ':' }) >= 0)
            throw new IOException("invalid extraction entry path");
        // LibHac uses one leading slash for paths relative to the archive root.
        string relative = entry.StartsWith("/", StringComparison.Ordinal) ? entry[1..] : entry;
        foreach (string component in relative.Split('/'))
            if (component.Length == 0 || component == "." || component == "..")
                throw new IOException("invalid extraction entry component");
        string fullRoot = Path.TrimEndingDirectorySeparator(Path.GetFullPath(root));
        string destination = Path.GetFullPath(Path.Combine(fullRoot, relative));
        string prefix = Path.EndsInDirectorySeparator(fullRoot) ? fullRoot : fullRoot + Path.DirectorySeparatorChar;
        if (!destination.StartsWith(prefix, StringComparison.Ordinal))
            throw new IOException("extraction entry escapes its root");
        RejectLinks(destination);
        return destination;
    }

    static void RejectLinks(string path) {
        // Check the leaf, dangling links, the root, and all existing ancestors.
        // Extraction runs in a fresh, private workspace, not a shared directory
        // that another process is allowed to change while extraction is active.
        for (string current = path; !string.IsNullOrEmpty(current); current = Path.GetDirectoryName(current)) {
            try {
                if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("extraction path contains a symbolic link");
            } catch (FileNotFoundException) {
                // A new output leaf or ancestor does not exist yet.
            } catch (DirectoryNotFoundException) {
                // Continue upwards to check the existing part of the path.
            }
        }
    }
}
