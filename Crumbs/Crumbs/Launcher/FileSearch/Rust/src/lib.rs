mod index;

use core_foundation::{
    array::{CFArray, CFArrayRef},
    base::{CFAllocatorRef, CFType, CFTypeRef, TCFType},
    runloop::{kCFRunLoopDefaultMode, CFRunLoopRunInMode},
    string::{CFString, CFStringRef},
};
use std::{
    cell::RefCell,
    collections::HashMap,
    ffi::{c_char, c_void, CStr, CString},
    path::Path,
    ptr,
};

#[link(name = "CoreServices", kind = "framework")]
extern "C" {
    static kUTTagClassFilenameExtension: CFStringRef;
    static kUTTypeImage: CFStringRef;
    static kUTTypeAudio: CFStringRef;
    fn UTTypeCreatePreferredIdentifierForTag(
        tag_class: CFStringRef,
        tag: CFStringRef,
        conforms_to: CFStringRef,
    ) -> CFStringRef;
    fn UTTypeConformsTo(identifier: CFStringRef, parent: CFStringRef) -> u8;
    fn MDQueryCreate(
        allocator: CFAllocatorRef,
        predicate: CFStringRef,
        values: CFArrayRef,
        sort: CFArrayRef,
    ) -> CFTypeRef;
    fn MDQuerySetSearchScope(query: CFTypeRef, scope: CFArrayRef, options: u32);
    fn MDQuerySetSortOptionFlagsForAttribute(query: CFTypeRef, key: CFStringRef, flags: u32) -> u8;
    fn MDQueryExecute(query: CFTypeRef, flags: usize) -> u8;
    fn MDQueryIsGatheringComplete(query: CFTypeRef) -> u8;
    fn MDQueryStop(query: CFTypeRef);
    fn MDQueryGetResultCount(query: CFTypeRef) -> isize;
    fn MDQueryGetResultAtIndex(query: CFTypeRef, index: isize) -> CFTypeRef;
    fn MDItemCopyAttribute(item: CFTypeRef, key: CFStringRef) -> CFTypeRef;
}

// Use the system's registered filename types through the existing CoreServices C bridge.
fn media_file(path: &Path) -> bool {
    let Some(ext) = path.extension().and_then(|e| e.to_str()) else {
        return false;
    };
    thread_local! {
        static TYPES: RefCell<HashMap<String, bool>> = RefCell::default();
    }
    TYPES.with_borrow_mut(|types| {
        if let Some(&media) = types.get(ext) {
            return media;
        }
        let tag = CFString::new(ext);
        let media = unsafe {
            let identifier = UTTypeCreatePreferredIdentifierForTag(
                kUTTagClassFilenameExtension,
                tag.as_concrete_TypeRef(),
                ptr::null(),
            );
            if identifier.is_null() {
                false
            } else {
                let ty = CFString::wrap_under_create_rule(identifier);
                UTTypeConformsTo(ty.as_concrete_TypeRef(), kUTTypeImage) != 0
                    || UTTypeConformsTo(ty.as_concrete_TypeRef(), kUTTypeAudio) != 0
            }
        };
        if types.len() < 4096 {
            types.insert(ext.to_owned(), media);
        }
        media
    })
}

/// # Safety
/// The caller supplies a valid, NUL-terminated filesystem path.
#[no_mangle]
pub unsafe extern "C" fn crumbs_inside_media_library(path: *const c_char) -> bool {
    use std::os::unix::ffi::OsStrExt;
    index::inside_media_library(Path::new(std::ffi::OsStr::from_bytes(
        CStr::from_ptr(path).to_bytes(),
    )))
}

type Cancelled = extern "C" fn(*mut c_void) -> bool;
type Append = extern "C" fn(*mut c_void, *const c_char, bool);

#[no_mangle]
pub extern "C" fn crumbs_index_revision() -> u64 {
    index::revision()
}

#[no_mangle]
pub extern "C" fn crumbs_stop_file_index() {
    index::stop();
}

#[no_mangle]
pub extern "C" fn crumbs_index_ready() -> bool {
    index::ready()
}

/// # Safety
/// The caller supplies a valid UTF-8 C string containing an absolute cache file path.
#[no_mangle]
pub unsafe extern "C" fn crumbs_start_file_index(cache: *const c_char) {
    if let Ok(path) = CStr::from_ptr(cache).to_str() {
        index::start(path.into());
    }
}

/// # Safety
/// The query string and callback context must remain valid until return.
#[no_mangle]
pub unsafe extern "C" fn crumbs_search_files(
    term: *const c_char,
    directory: *const c_char,
    context: *mut c_void,
    cancelled: Cancelled,
    append: Append,
) -> bool {
    let Ok(term) = CStr::from_ptr(term).to_str() else {
        return false;
    };
    let directory = if directory.is_null() {
        None
    } else {
        let Ok(path) = CStr::from_ptr(directory).to_str() else {
            return false;
        };
        Some(Path::new(path))
    };
    let Some(results) = index::search(term, directory, || cancelled(context)) else {
        return false;
    };
    for (path, folder) in results {
        if cancelled(context) {
            return false;
        }
        if let Ok(path) = CString::new(path.as_os_str().as_encoded_bytes()) {
            append(context, path.as_ptr(), folder);
        }
    }
    true
}

fn attribute(item: CFTypeRef, key: &CFString) -> Option<String> {
    unsafe {
        let value = MDItemCopyAttribute(item, key.as_concrete_TypeRef());
        if value.is_null() {
            return None;
        }
        CFType::wrap_under_create_rule(value)
            .downcast::<CFString>()
            .map(|s| s.to_string())
    }
}

/// # Safety
/// The caller supplies a valid UTF-8 C string and callbacks whose context lives until return.
#[no_mangle]
pub unsafe extern "C" fn crumbs_recent_files(
    predicate: *const c_char,
    scope: *const c_char,
    context: *mut c_void,
    cancelled: Cancelled,
    append: Append,
) -> bool {
    if cancelled(context) {
        return false;
    }
    let (Ok(predicate), Ok(scope)) = (
        CStr::from_ptr(predicate).to_str(),
        CStr::from_ptr(scope).to_str(),
    ) else {
        return false;
    };
    let predicate = CFString::new(&format!(
        r#"({predicate}) && (kMDItemContentTypeTree != "public.image") && (kMDItemContentTypeTree != "public.audio")"#
    ));
    let path_key = CFString::new("kMDItemPath");
    let type_key = CFString::new("kMDItemContentType");
    let sort_key = CFString::new("kMDItemLastUsedDate");
    let sort = CFArray::from_CFTypes(std::slice::from_ref(&sort_key));
    let raw = MDQueryCreate(
        ptr::null(),
        predicate.as_concrete_TypeRef(),
        ptr::null(),
        sort.as_concrete_TypeRef(),
    );
    if raw.is_null() {
        return false;
    }
    let _owner = CFType::wrap_under_create_rule(raw);
    let scopes = CFArray::from_CFTypes(&[CFString::new(scope)]);
    MDQuerySetSearchScope(raw, scopes.as_concrete_TypeRef(), 0);
    MDQuerySetSortOptionFlagsForAttribute(raw, sort_key.as_concrete_TypeRef(), 1);
    if MDQueryExecute(raw, 0) == 0 {
        return false;
    }
    // Pump this worker's run loop so cancellation also interrupts Spotlight gathering.
    while MDQueryIsGatheringComplete(raw) == 0 {
        if cancelled(context) {
            MDQueryStop(raw);
            return false;
        }
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.025, 1);
    }
    for index in 0..MDQueryGetResultCount(raw) {
        if cancelled(context) {
            return false;
        }
        let item = MDQueryGetResultAtIndex(raw, index);
        if item.is_null() {
            continue;
        }
        let Some(path) = attribute(item, &path_key) else {
            continue;
        };
        if media_file(Path::new(&path)) || index::inside_media_library(Path::new(&path)) {
            continue;
        }
        if Path::new(&path)
            .components()
            .any(|p| p.as_os_str().as_encoded_bytes().starts_with(b"."))
        {
            continue;
        }
        let Ok(path) = CString::new(path) else {
            continue;
        };
        append(
            context,
            path.as_ptr(),
            attribute(item, &type_key).as_deref() == Some("public.folder"),
        );
    }
    true
}
