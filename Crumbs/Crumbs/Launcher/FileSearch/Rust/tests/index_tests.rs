use super::*;
use std::sync::atomic::AtomicUsize;

fn crawl(root: &Path) -> Entries {
    let catalog = Catalog::default();
    rebuild(root, &catalog);
    catalog.entries.into_inner().unwrap()
}

struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        let id = NEXT.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir()
            .canonicalize()
            .unwrap()
            .join(format!("crumbs-index-{}-{id}", std::process::id()));
        fs::create_dir(&path).unwrap();
        Self(path)
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

#[test]
fn fuzzy_results_and_incremental_updates_use_the_same_ignore_rules_as_the_crawl() {
    let fixture = Fixture::new();
    let root = &fixture.0;
    fs::write(root.join(".gitignore"), "*.generated\n").unwrap();
    for name in ["QuarterlyBudget.xlsx", "draft.generated", ".secret"] {
        fs::write(root.join(name), "").unwrap();
    }
    let catalog = Catalog::default();
    rebuild(root, &catalog);
    let entries = catalog.entries.read().unwrap();
    assert_eq!(entries.len(), 2);
    assert_eq!(
        ranked(&entries, "qbud", None, &|| false).unwrap()[0].0,
        root.join("QuarterlyBudget.xlsx")
    );
    assert!(ranked(&entries, "qbud", None, &|| true).is_none());
    drop(entries);
    let renamed = root.join("Budget2026.xlsx");
    fs::rename(root.join("QuarterlyBudget.xlsx"), &renamed).unwrap();
    update(&catalog, &root.join("QuarterlyBudget.xlsx"));
    update(&catalog, &renamed);
    assert!(!update(&catalog, &root.join("draft.generated")));
    assert_eq!(*catalog.entries.read().unwrap(), crawl(root));
    let cache = root.join(".snapshot");
    save(&cache, &catalog.entries.read().unwrap()).unwrap();
    let restored: Entries = serde_json::from_reader(File::open(&cache).unwrap()).unwrap();
    assert_eq!(restored, crawl(root));
}

#[test]
fn moved_subtrees_are_removed_without_touching_similarly_named_siblings() {
    let fixture = Fixture::new();
    let root = &fixture.0;
    for name in ["notes", "notes-old"] {
        fs::create_dir(root.join(name)).unwrap();
        fs::write(root.join(name).join("entry.txt"), "").unwrap();
    }
    let catalog = Catalog::default();
    rebuild(root, &catalog);
    fs::rename(root.join("notes"), root.join("archive")).unwrap();
    update(&catalog, &root.join("notes"));
    update(&catalog, &root.join("archive"));
    assert_eq!(*catalog.entries.read().unwrap(), crawl(root));
}

#[test]
#[ignore = "requires the macOS FSEvents service"]
fn live_watcher_indexes_create_rename_delete() {
    let fixture = Fixture::new();
    let root = fixture.0.join("files");
    fs::create_dir(&root).unwrap();
    let cache = fixture.0.join("cache.json");
    let catalog = Catalog::default();
    thread::scope(|scope| {
        scope.spawn(|| maintain(&root, &cache, &catalog));
        struct Stop<'a>(&'a Catalog);
        impl Drop for Stop<'_> {
            fn drop(&mut self) {
                self.0.stopping.store(true, Ordering::Release);
            }
        }
        let _stop = Stop(&catalog);
        let wait = |condition: &dyn Fn() -> bool| {
            let deadline = Instant::now() + Duration::from_secs(10);
            while !condition() {
                assert!(
                    Instant::now() < deadline,
                    "timed out waiting for index update"
                );
                thread::sleep(Duration::from_millis(50));
            }
        };
        wait(&|| cache.is_file());
        let file = root.join("sample.txt");
        let renamed = root.join("renamed.txt");
        fs::write(&file, "test").unwrap();
        wait(&|| catalog.entries.read().unwrap().contains_key(&file));
        fs::rename(&file, &renamed).unwrap();
        wait(&|| {
            let entries = catalog.entries.read().unwrap();
            entries.contains_key(&renamed) && !entries.contains_key(&file)
        });
        fs::remove_file(&renamed).unwrap();
        wait(&|| !catalog.entries.read().unwrap().contains_key(&renamed));
    });
}

#[test]
fn media_libraries_stay_out_of_the_index_after_file_events() {
    let fixture = Fixture::new();
    let root = &fixture.0;
    for dir in [
        "Users/person",
        "Library/Containers",
        "Library/Application Support",
    ] {
        fs::create_dir_all(root.join(dir)).unwrap();
    }
    let catalog = Catalog::default();
    rebuild(root, &catalog);
    for name in [
        "Family.PHOTOSLIBRARY",
        "Library.musiclibrary",
        "Music/Music",
        "Users/person/Music",
        "Users/person/Pictures",
        "Library/Containers/com.apple.Photos",
        "Library/Application Support/iTunes",
    ] {
        let library = root.join(name);
        fs::create_dir_all(&library).unwrap();
        let child = library.join("metadata.txt");
        fs::write(&child, "").unwrap();
        update(&catalog, &root.join("Music"));
        update(&catalog, &library);
        update(&catalog, &child);
        let entries = catalog.entries.read().unwrap();
        assert!(!entries.contains_key(&library));
        assert!(!entries.contains_key(&child));
    }
    assert_eq!(*catalog.entries.read().unwrap(), crawl(root));
}

#[test]
fn media_types_are_excluded_but_documents_and_directories_remain_searchable() {
    let fixture = Fixture::new();
    let root = &fixture.0;
    let catalog = Catalog::default();
    rebuild(root, &catalog);
    for name in [
        "photo.HEIC",
        "scan.JPEG",
        "picture.png",
        "song.MP3",
        "music.m4a",
        "report.pdf",
    ] {
        let file = root.join(name);
        fs::write(&file, "").unwrap();
        update(&catalog, &file);
    }
    let folder = root.join("archive.jpg");
    fs::create_dir(&folder).unwrap();
    update(&catalog, &folder);
    let rows = catalog.entries.read().unwrap();
    assert_eq!(rows.get(&folder), Some(&true));
    assert_eq!(rows.get(&root.join("report.pdf")), Some(&false));
    assert_eq!(rows.len(), 3);
    assert_eq!(*rows, crawl(root));
}

#[test]
fn media_events_and_spotlight_results_exclude_nested_documents() {
    for path in [
        "/Users/person/Pictures/album/notes.pdf",
        "/Users/person/Music/song.txt",
        "/Volumes/Backup/Family.PHOTOSLIBRARY/database/record.txt",
        "/Users/person/Library/Group Containers/group.com.apple.music/settings.json",
    ] {
        let path = Path::new(path);
        assert!(inside_media_library(path));
        let mut paths = BTreeSet::new();
        let event = Event::new(EventKind::Any).add_path(path.to_owned());
        assert!(changes(Ok(event), &mut paths));
        assert!(paths.is_empty());
    }
    assert!(!inside_media_library(Path::new(
        "/Users/person/Documents/Music/notes.pdf"
    )));
}

#[test]
fn folder_browsing_lists_every_direct_child_and_filters_within_the_folder() {
    let directory = Path::new("/project");
    let mut entries = Entries::new();
    for i in 0..110 {
        entries.insert(directory.join(format!("file-{i}")), false);
    }
    let folder = directory.join("notes");
    entries.insert(folder.clone(), true);
    entries.insert(folder.join("file-deep"), false);
    entries.insert(PathBuf::from("/project-old/file-outside"), false);
    let list = ranked(&entries, "", Some(directory), &|| false).unwrap();
    assert_eq!(list.len(), 111);
    assert!(list.iter().all(|(p, _)| p.parent() == Some(directory)));
    assert_eq!(
        ranked(&entries, "nts", Some(directory), &|| false).unwrap(),
        vec![(folder, true)]
    );
    assert!(ranked(&entries, "deep", Some(directory), &|| false)
        .unwrap()
        .is_empty());
}
