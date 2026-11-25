//! Process-owned filename catalog. One worker owns crawling, watching and persistence.
use ignore::{DirEntry, WalkBuilder, WalkState};
use notify::{event::ModifyKind, Event, EventKind, RecursiveMode, Watcher};
use nucleo_matcher::{
    pattern::{AtomKind, CaseMatching, Normalization, Pattern},
    Config, Matcher, Utf32Str,
};
use std::{
    cmp::Reverse,
    collections::{BTreeMap, BTreeSet, BinaryHeap},
    fs::{self, File, OpenOptions},
    io::{self, BufReader, BufWriter, Write},
    os::unix::{ffi::OsStrExt, fs::OpenOptionsExt},
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        mpsc, Arc, OnceLock, RwLock,
    },
    thread,
    time::{Duration, Instant},
};

type Entries = BTreeMap<PathBuf, bool>;
#[derive(Default)]
struct Catalog {
    entries: RwLock<Entries>,
    revision: AtomicU64,
    complete: AtomicBool,
    stopping: AtomicBool,
}

static INDEX: OnceLock<Arc<Catalog>> = OnceLock::new();

pub fn start(cache: PathBuf) {
    INDEX.get_or_init(|| {
        let catalog = Arc::new(Catalog::default());
        let worker = catalog.clone();
        thread::spawn(move || maintain(Path::new("/"), &cache, &worker));
        catalog
    });
}

pub fn stop() {
    if let Some(index) = INDEX.get() {
        index.stopping.store(true, Ordering::Release);
    }
}

pub fn search(
    term: &str,
    directory: Option<&Path>,
    cancelled: impl Fn() -> bool,
) -> Option<Vec<(PathBuf, bool)>> {
    let index = INDEX.get()?;
    let entries = index.entries.read().ok()?;
    ranked(&entries, term, directory, &cancelled)
}

pub fn revision() -> u64 {
    INDEX
        .get()
        .map_or(0, |i| i.revision.load(Ordering::Acquire))
}

pub fn ready() -> bool {
    INDEX
        .get()
        .is_some_and(|i| i.complete.load(Ordering::Acquire))
}

fn ranked(
    entries: &Entries,
    term: &str,
    directory: Option<&Path>,
    cancelled: &impl Fn() -> bool,
) -> Option<Vec<(PathBuf, bool)>> {
    let pattern = Pattern::new(
        term,
        CaseMatching::Ignore,
        Normalization::Smart,
        AtomKind::Fuzzy,
    );
    let mut matcher = Matcher::new(Config::DEFAULT);
    let mut buffer = Vec::new();
    let mut best = BinaryHeap::new();
    let start = directory.unwrap_or(Path::new("")).to_owned();
    let mut children = Vec::new();
    for (i, (path, folder)) in entries.range(start..).enumerate() {
        if i % 256 == 0 && cancelled() {
            return None;
        }
        if let Some(directory) = directory {
            if !path.starts_with(directory) {
                break;
            }
            if path.parent() != Some(directory) {
                continue;
            }
            if term.is_empty() {
                children.push((path.clone(), *folder));
                continue;
            }
        }
        let Some(name) = path.file_name().and_then(|s| s.to_str()) else {
            continue;
        };
        if let Some(score) = pattern.score(Utf32Str::new(name, &mut buffer), &mut matcher) {
            let hit = (
                Reverse(name.eq_ignore_ascii_case(term)),
                Reverse(score),
                path,
                *folder,
            );
            if best.len() < 100 {
                best.push(hit);
            } else if best.peek().is_some_and(|worst| hit < *worst) {
                best.pop();
                best.push(hit);
            }
        }
    }
    if directory.is_some() && term.is_empty() {
        return Some(children);
    }
    Some(
        best.into_sorted_vec()
            .into_iter()
            .map(|(_, _, path, folder)| (path.clone(), folder))
            .collect(),
    )
}

fn media_library(path: &Path) -> bool {
    let ext = path.extension().and_then(|ext| ext.to_str()).unwrap_or("");
    if [
        "photoslibrary",
        "photolibrary",
        "migratedphotolibrary",
        "aplibrary",
        "musiclibrary",
        "itl",
    ]
    .iter()
    .any(|library| ext.eq_ignore_ascii_case(library))
    {
        return true;
    }
    let name = path.file_name().unwrap_or_default().as_bytes();
    let parent = path.parent().unwrap_or(Path::new(""));
    static HOME: OnceLock<Option<PathBuf>> = OnceLock::new();
    let home = HOME.get_or_init(|| std::env::var_os("HOME").map(PathBuf::from));
    if (name.eq_ignore_ascii_case(b"Music") || name.eq_ignore_ascii_case(b"Pictures"))
        && (home.as_deref() == Some(parent)
            || parent.parent().is_some_and(|p| p.ends_with("Users")))
    {
        return true;
    }
    if path.ends_with("Music/Music") || path.ends_with("Music/iTunes") {
        return true;
    }
    // Apple also keeps media databases outside the visible library packages.
    let library_data = parent.ends_with("Library")
        || parent.ends_with("Library/Application Support")
        || parent.ends_with("Library/Containers")
        || parent.ends_with("Library/Group Containers");
    if library_data {
        let name = name.to_ascii_lowercase();
        return matches!(
            name.as_slice(),
            b"photos" | b"music" | b"itunes" | b"ilifemediabrowser" | b"medialibrary"
        ) || [
            b"com.apple.photos".as_slice(),
            b"com.apple.music",
            b"com.apple.itunes",
            b"com.apple.photolibrary",
            b"group.com.apple.photos",
            b"group.com.apple.music",
        ]
        .iter()
        .any(|prefix| name.starts_with(prefix));
    }
    false
}

pub(super) fn inside_media_library(path: &Path) -> bool {
    path.ancestors().any(media_library)
}

fn visible(entry: &DirEntry) -> bool {
    let path = entry.path();
    let Some(kind) = entry.file_type() else {
        return false;
    };
    if !(kind.is_file() || kind.is_dir()) || path.to_str().is_none() || media_library(path) {
        return false;
    }
    if path == Path::new("/System/Volumes")
        || path == Path::new("/private")
        || path == Path::new("/dev")
        || path == Path::new("/net")
        || path == Path::new("/Network")
    {
        return false;
    }
    let name = entry.file_name().as_bytes();
    if name.starts_with(b".") {
        return false;
    }
    if kind.is_file() && super::media_file(path) {
        return false;
    }
    if kind.is_dir() {
        if name == b"node_modules"
            || name == b"DerivedData"
            || name == b"Caches"
            || path
                .extension()
                .is_some_and(|ext| ext.eq_ignore_ascii_case("app"))
        {
            return false;
        }
        if path.parent() == Some(Path::new("/Volumes")) {
            let Ok(path) = std::ffi::CString::new(path.as_os_str().as_bytes()) else {
                return false;
            };
            let mut info = std::mem::MaybeUninit::uninit();
            return unsafe {
                libc::statfs(path.as_ptr(), info.as_mut_ptr()) == 0
                    && info.assume_init().f_flags & libc::MNT_LOCAL as u32 != 0
            };
        }
    }
    true
}

fn walker(root: &Path) -> WalkBuilder {
    let mut builder = WalkBuilder::new(root);
    builder
        .follow_links(false)
        .require_git(false)
        .filter_entry(visible);
    builder
}

// Each walker flushes its last partial batch when the thread finishes.
struct Batch<'a> {
    rows: Vec<(PathBuf, bool)>,
    destination: &'a RwLock<Entries>,
    revision: &'a AtomicU64,
}
impl Batch<'_> {
    fn flush(&mut self) {
        if !self.rows.is_empty() {
            self.destination
                .write()
                .unwrap()
                .extend(self.rows.drain(..));
            self.revision.fetch_add(1, Ordering::Release);
        }
    }
    fn push(&mut self, entry: DirEntry) {
        self.rows.push((
            entry.path().to_owned(),
            entry.file_type().is_some_and(|ty| ty.is_dir()),
        ));
        if self.rows.len() == 512 {
            self.flush();
        }
    }
}
impl Drop for Batch<'_> {
    fn drop(&mut self) {
        self.flush();
    }
}

fn rebuild(root: &Path, catalog: &Catalog) {
    let staging = Catalog::default();
    // With a warm cache, keep serving it until reconciliation finishes. Cold walks publish in batches.
    let warm = catalog.complete.load(Ordering::Acquire);
    let target = if warm { &staging } else { catalog };
    walker(root).threads(4).build_parallel().run(|| {
        let mut batch = Batch {
            rows: Vec::with_capacity(512),
            destination: &target.entries,
            revision: &target.revision,
        };
        Box::new(move |result| {
            if catalog.stopping.load(Ordering::Acquire) {
                return WalkState::Quit;
            }
            if let Ok(entry) = result {
                batch.push(entry);
            }
            WalkState::Continue
        })
    });
    if catalog.stopping.load(Ordering::Acquire) {
        return;
    }
    if warm {
        *catalog.entries.write().unwrap() = staging.entries.into_inner().unwrap();
    }
    catalog.complete.store(true, Ordering::Release);
    catalog.revision.fetch_add(1, Ordering::Release);
}

// Walk the parent one level so the same inherited gitignore rules apply to new paths.
fn replacement(path: &Path) -> Entries {
    let Some(parent) = path.parent() else {
        return Entries::new();
    };
    if inside_media_library(path) {
        return Entries::new();
    }
    let target = path.to_owned();
    let entries = std::sync::Mutex::new(Entries::new());
    // The serial walker opens directories before applying its filter. The parallel
    // walker filters children before scheduling them for directory or ignore-file reads.
    walker(parent)
        .filter_entry(move |entry| (entry.depth() != 1 || entry.path() == target) && visible(entry))
        .threads(1)
        .build_parallel()
        .run(|| {
            Box::new(|result| {
                if let Ok(entry) = result {
                    if entry.depth() > 0 {
                        entries.lock().unwrap().insert(
                            entry.path().to_owned(),
                            entry.file_type().is_some_and(|ty| ty.is_dir()),
                        );
                    }
                }
                WalkState::Continue
            })
        });
    entries.into_inner().unwrap()
}

fn update(catalog: &Catalog, path: &Path) -> bool {
    let Some(parent) = path.parent() else {
        return false;
    };
    if catalog.entries.read().unwrap().get(parent) != Some(&true) {
        return false;
    }
    let fresh = replacement(path);
    let mut entries = catalog.entries.write().unwrap();
    // Path ordering groups descendants by component, including the path itself.
    let obsolete: Vec<_> = entries
        .range(path.to_owned()..)
        .take_while(|(p, _)| p.starts_with(path))
        .map(|(p, _)| p.clone())
        .collect();
    if obsolete.len() == fresh.len() && obsolete.iter().all(|p| entries.get(p) == fresh.get(p)) {
        return false;
    }
    for p in obsolete {
        entries.remove(&p);
    }
    entries.extend(fresh);
    catalog.revision.fetch_add(1, Ordering::Release);
    true
}

fn save(cache: &Path, entries: &Entries) -> io::Result<()> {
    fs::create_dir_all(cache.parent().unwrap())?;
    let temp = cache.with_extension(format!("{}.tmp", std::process::id()));
    let file = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .mode(0o600)
        .open(&temp)?;
    let mut writer = BufWriter::new(file);
    serde_json::to_writer(&mut writer, entries)?;
    writer.flush()?;
    fs::rename(temp, cache)
}

fn changes(event: notify::Result<Event>, paths: &mut BTreeSet<PathBuf>) -> bool {
    let Ok(event) = event else { return false };
    if event.need_rescan() {
        return false;
    }
    for path in event.paths {
        let path = match path.strip_prefix("/System/Volumes/Data") {
            Ok(rest) => Path::new("/").join(rest),
            Err(_) => path,
        };
        if inside_media_library(&path) {
            continue;
        }
        let ignores_changed = matches!(
            path.file_name().and_then(|n| n.to_str()),
            Some(".gitignore" | ".ignore")
        );
        if ignores_changed {
            if let Some(parent) = path.parent() {
                paths.insert(parent.to_owned());
            }
        } else if !matches!(
            event.kind,
            EventKind::Access(_) | EventKind::Modify(ModifyKind::Data(_))
        ) && !path
            .components()
            .any(|p| p.as_os_str().as_bytes().starts_with(b"."))
        {
            paths.insert(path);
        }
    }
    true
}

fn maintain(root: &Path, cache: &Path, catalog: &Catalog) {
    if let Ok(file) = File::open(cache) {
        if let Ok(entries) = serde_json::from_reader(BufReader::new(file)) {
            *catalog.entries.write().unwrap() = entries;
            catalog.complete.store(true, Ordering::Release);
            catalog.revision.fetch_add(1, Ordering::Release);
        }
    }
    while !catalog.stopping.load(Ordering::Acquire) {
        let (sender, receiver) = mpsc::sync_channel(8192);
        let overflow = Arc::new(AtomicBool::new(false));
        let dropped = overflow.clone();
        // Subscribe before walking. Events occurring during the crawl are replayed afterward.
        let watcher = notify::recommended_watcher(move |event| {
            if let Err(mpsc::TrySendError::Full(_)) = sender.try_send(event) {
                dropped.store(true, Ordering::Release);
            }
        })
        .and_then(|mut watcher| {
            watcher.watch(root, RecursiveMode::Recursive)?;
            Ok(watcher)
        });
        rebuild(root, catalog);
        if catalog.stopping.load(Ordering::Acquire) {
            return;
        }
        let persist = || {
            let _ = save(cache, &catalog.entries.read().unwrap());
        };
        persist();
        let Ok(_watcher) = watcher else {
            thread::sleep(Duration::from_secs(60));
            continue;
        };
        let mut dirty = false;
        let mut saved = Instant::now();
        while !catalog.stopping.load(Ordering::Acquire) {
            if overflow.load(Ordering::Acquire) {
                break;
            }
            let mut paths = BTreeSet::new();
            match receiver.recv_timeout(Duration::from_secs(2)) {
                Ok(event) => {
                    thread::sleep(Duration::from_millis(150));
                    if !std::iter::once(event)
                        .chain(receiver.try_iter())
                        .all(|ev| changes(ev, &mut paths))
                        || paths.contains(root)
                    {
                        break;
                    }
                    let mut previous: Option<PathBuf> = None;
                    for path in paths {
                        if previous.as_ref().is_some_and(|p| path.starts_with(p)) {
                            continue;
                        }
                        dirty |= update(catalog, &path);
                        previous = Some(path);
                    }
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {}
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
            }
            if dirty && saved.elapsed() >= Duration::from_secs(60) {
                persist();
                dirty = false;
                saved = Instant::now();
            }
        }
    }
}

#[cfg(test)]
#[path = "../tests/index_tests.rs"]
mod tests;
