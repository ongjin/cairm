public func new_engine() -> Engine {
    Engine(ptr: __swift_bridge__$new_engine())
}
public func searchStart<GenericIntoRustString: IntoRustString>(_ root_path: GenericIntoRustString, _ query: GenericIntoRustString, _ subtree: Bool, _ show_hidden: Bool) -> UInt64 {
    __swift_bridge__$search_start({ let rustString = root_path.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), { let rustString = query.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), subtree, show_hidden)
}
public func searchNextBatch(_ handle: UInt64) -> SearchBatch {
    SearchBatch(ptr: __swift_bridge__$search_next_batch(handle))
}
public func searchCancel(_ handle: UInt64) {
    __swift_bridge__$search_cancel(handle)
}
public enum FileKind {
    case Directory
    case Regular
    case Symlink
}
extension FileKind {
    func intoFfiRepr() -> __swift_bridge__$FileKind {
        switch self {
            case FileKind.Directory:
                return __swift_bridge__$FileKind(tag: __swift_bridge__$FileKind$Directory)
            case FileKind.Regular:
                return __swift_bridge__$FileKind(tag: __swift_bridge__$FileKind$Regular)
            case FileKind.Symlink:
                return __swift_bridge__$FileKind(tag: __swift_bridge__$FileKind$Symlink)
        }
    }
}
extension __swift_bridge__$FileKind {
    func intoSwiftRepr() -> FileKind {
        switch self.tag {
            case __swift_bridge__$FileKind$Directory:
                return FileKind.Directory
            case __swift_bridge__$FileKind$Regular:
                return FileKind.Regular
            case __swift_bridge__$FileKind$Symlink:
                return FileKind.Symlink
            default:
                fatalError("Unreachable")
        }
    }
}
extension __swift_bridge__$Option$FileKind {
    @inline(__always)
    func intoSwiftRepr() -> Optional<FileKind> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }
    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<FileKind>) -> __swift_bridge__$Option$FileKind {
        if let v = val {
            return __swift_bridge__$Option$FileKind(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$FileKind(is_some: false, val: __swift_bridge__$FileKind())
        }
    }
}
extension FileKind: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_FileKind$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_FileKind$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: Self) {
        __swift_bridge__$Vec_FileKind$push(vecPtr, value.intoFfiRepr())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let maybeEnum = __swift_bridge__$Vec_FileKind$pop(vecPtr)
        return maybeEnum.intoSwiftRepr()
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<Self> {
        let maybeEnum = __swift_bridge__$Vec_FileKind$get(vecPtr, index)
        return maybeEnum.intoSwiftRepr()
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<Self> {
        let maybeEnum = __swift_bridge__$Vec_FileKind$get_mut(vecPtr, index)
        return maybeEnum.intoSwiftRepr()
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<Self> {
        UnsafePointer<Self>(OpaquePointer(__swift_bridge__$Vec_FileKind$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_FileKind$len(vecPtr)
    }
}
public enum IconKind {
    case Folder
    case GenericFile
    case ExtensionHint(RustString)
}
extension IconKind {
    func intoFfiRepr() -> __swift_bridge__$IconKind {
        switch self {
            case IconKind.Folder:
                return {var val = __swift_bridge__$IconKind(); val.tag = __swift_bridge__$IconKind$Folder; return val }()
            case IconKind.GenericFile:
                return {var val = __swift_bridge__$IconKind(); val.tag = __swift_bridge__$IconKind$GenericFile; return val }()
            case IconKind.ExtensionHint(let _0):
                return __swift_bridge__$IconKind(tag: __swift_bridge__$IconKind$ExtensionHint, payload: __swift_bridge__$IconKindFields(ExtensionHint: __swift_bridge__$IconKind$FieldOfExtensionHint(_0: { let rustString = _0.intoRustString(); rustString.isOwned = false; return rustString.ptr }())))
        }
    }
}
extension __swift_bridge__$IconKind {
    func intoSwiftRepr() -> IconKind {
        switch self.tag {
            case __swift_bridge__$IconKind$Folder:
                return IconKind.Folder
            case __swift_bridge__$IconKind$GenericFile:
                return IconKind.GenericFile
            case __swift_bridge__$IconKind$ExtensionHint:
                return IconKind.ExtensionHint(RustString(ptr: self.payload.ExtensionHint._0))
            default:
                fatalError("Unreachable")
        }
    }
}
extension __swift_bridge__$Option$IconKind {
    @inline(__always)
    func intoSwiftRepr() -> Optional<IconKind> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }
    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<IconKind>) -> __swift_bridge__$Option$IconKind {
        if let v = val {
            return __swift_bridge__$Option$IconKind(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$IconKind(is_some: false, val: __swift_bridge__$IconKind())
        }
    }
}
public struct FileEntry {
    public var path: RustString
    public var name: RustString
    public var size: UInt64
    public var modified_unix: Int64
    public var kind: FileKind
    public var is_hidden: Bool
    public var icon_kind: IconKind

    public init(path: RustString,name: RustString,size: UInt64,modified_unix: Int64,kind: FileKind,is_hidden: Bool,icon_kind: IconKind) {
        self.path = path
        self.name = name
        self.size = size
        self.modified_unix = modified_unix
        self.kind = kind
        self.is_hidden = is_hidden
        self.icon_kind = icon_kind
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$FileEntry {
        { let val = self; return __swift_bridge__$FileEntry(path: { let rustString = val.path.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), name: { let rustString = val.name.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), size: val.size, modified_unix: val.modified_unix, kind: val.kind.intoFfiRepr(), is_hidden: val.is_hidden, icon_kind: val.icon_kind.intoFfiRepr()); }()
    }
}
extension __swift_bridge__$FileEntry {
    @inline(__always)
    func intoSwiftRepr() -> FileEntry {
        { let val = self; return FileEntry(path: RustString(ptr: val.path), name: RustString(ptr: val.name), size: val.size, modified_unix: val.modified_unix, kind: val.kind.intoSwiftRepr(), is_hidden: val.is_hidden, icon_kind: val.icon_kind.intoSwiftRepr()); }()
    }
}
extension __swift_bridge__$Option$FileEntry {
    @inline(__always)
    func intoSwiftRepr() -> Optional<FileEntry> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<FileEntry>) -> __swift_bridge__$Option$FileEntry {
        if let v = val {
            return __swift_bridge__$Option$FileEntry(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$FileEntry(is_some: false, val: __swift_bridge__$FileEntry())
        }
    }
}
public enum WalkerError {
    case PermissionDenied
    case NotFound
    case NotDirectory
    case Io(RustString)
}
extension WalkerError {
    func intoFfiRepr() -> __swift_bridge__$WalkerError {
        switch self {
            case WalkerError.PermissionDenied:
                return {var val = __swift_bridge__$WalkerError(); val.tag = __swift_bridge__$WalkerError$PermissionDenied; return val }()
            case WalkerError.NotFound:
                return {var val = __swift_bridge__$WalkerError(); val.tag = __swift_bridge__$WalkerError$NotFound; return val }()
            case WalkerError.NotDirectory:
                return {var val = __swift_bridge__$WalkerError(); val.tag = __swift_bridge__$WalkerError$NotDirectory; return val }()
            case WalkerError.Io(let _0):
                return __swift_bridge__$WalkerError(tag: __swift_bridge__$WalkerError$Io, payload: __swift_bridge__$WalkerErrorFields(Io: __swift_bridge__$WalkerError$FieldOfIo(_0: { let rustString = _0.intoRustString(); rustString.isOwned = false; return rustString.ptr }())))
        }
    }
}
extension __swift_bridge__$WalkerError {
    func intoSwiftRepr() -> WalkerError {
        switch self.tag {
            case __swift_bridge__$WalkerError$PermissionDenied:
                return WalkerError.PermissionDenied
            case __swift_bridge__$WalkerError$NotFound:
                return WalkerError.NotFound
            case __swift_bridge__$WalkerError$NotDirectory:
                return WalkerError.NotDirectory
            case __swift_bridge__$WalkerError$Io:
                return WalkerError.Io(RustString(ptr: self.payload.Io._0))
            default:
                fatalError("Unreachable")
        }
    }
}
extension __swift_bridge__$Option$WalkerError {
    @inline(__always)
    func intoSwiftRepr() -> Optional<WalkerError> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }
    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<WalkerError>) -> __swift_bridge__$Option$WalkerError {
        if let v = val {
            return __swift_bridge__$Option$WalkerError(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$WalkerError(is_some: false, val: __swift_bridge__$WalkerError())
        }
    }
}
public enum PreviewError {
    case Binary
    case NotFound
    case PermissionDenied
    case Io(RustString)
}
extension PreviewError {
    func intoFfiRepr() -> __swift_bridge__$PreviewError {
        switch self {
            case PreviewError.Binary:
                return {var val = __swift_bridge__$PreviewError(); val.tag = __swift_bridge__$PreviewError$Binary; return val }()
            case PreviewError.NotFound:
                return {var val = __swift_bridge__$PreviewError(); val.tag = __swift_bridge__$PreviewError$NotFound; return val }()
            case PreviewError.PermissionDenied:
                return {var val = __swift_bridge__$PreviewError(); val.tag = __swift_bridge__$PreviewError$PermissionDenied; return val }()
            case PreviewError.Io(let _0):
                return __swift_bridge__$PreviewError(tag: __swift_bridge__$PreviewError$Io, payload: __swift_bridge__$PreviewErrorFields(Io: __swift_bridge__$PreviewError$FieldOfIo(_0: { let rustString = _0.intoRustString(); rustString.isOwned = false; return rustString.ptr }())))
        }
    }
}
extension __swift_bridge__$PreviewError {
    func intoSwiftRepr() -> PreviewError {
        switch self.tag {
            case __swift_bridge__$PreviewError$Binary:
                return PreviewError.Binary
            case __swift_bridge__$PreviewError$NotFound:
                return PreviewError.NotFound
            case __swift_bridge__$PreviewError$PermissionDenied:
                return PreviewError.PermissionDenied
            case __swift_bridge__$PreviewError$Io:
                return PreviewError.Io(RustString(ptr: self.payload.Io._0))
            default:
                fatalError("Unreachable")
        }
    }
}
extension __swift_bridge__$Option$PreviewError {
    @inline(__always)
    func intoSwiftRepr() -> Optional<PreviewError> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }
    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<PreviewError>) -> __swift_bridge__$Option$PreviewError {
        if let v = val {
            return __swift_bridge__$Option$PreviewError(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$PreviewError(is_some: false, val: __swift_bridge__$PreviewError())
        }
    }
}

public class Engine: EngineRefMut {
    var isOwned: Bool = true

    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }

    deinit {
        if isOwned {
            __swift_bridge__$Engine$_free(ptr)
        }
    }
}
public class EngineRefMut: EngineRef {
    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }
}
extension EngineRefMut {
    public func set_show_hidden(_ show: Bool) {
        __swift_bridge__$Engine$set_show_hidden(ptr, show)
    }
}
public class EngineRef {
    var ptr: UnsafeMutableRawPointer

    public init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }
}
extension EngineRef {
    public func list_directory<GenericIntoRustString: IntoRustString>(_ path: GenericIntoRustString) throws -> FileListing {
        try { let val = __swift_bridge__$Engine$list_directory(ptr, { let rustString = path.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); switch val.tag { case __swift_bridge__$ResultFileListingAndWalkerError$ResultOk: return FileListing(ptr: val.payload.ok) case __swift_bridge__$ResultFileListingAndWalkerError$ResultErr: throw val.payload.err.intoSwiftRepr() default: fatalError() } }()
    }

    public func preview_text<GenericIntoRustString: IntoRustString>(_ path: GenericIntoRustString) throws -> RustString {
        try { let val = __swift_bridge__$Engine$preview_text(ptr, { let rustString = path.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); switch val.tag { case __swift_bridge__$ResultStringAndPreviewError$ResultOk: return RustString(ptr: val.payload.ok) case __swift_bridge__$ResultStringAndPreviewError$ResultErr: throw val.payload.err.intoSwiftRepr() default: fatalError() } }()
    }
}
extension Engine: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_Engine$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_Engine$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: Engine) {
        __swift_bridge__$Vec_Engine$push(vecPtr, {value.isOwned = false; return value.ptr;}())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let pointer = __swift_bridge__$Vec_Engine$pop(vecPtr)
        if pointer == nil {
            return nil
        } else {
            return (Engine(ptr: pointer!) as! Self)
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<EngineRef> {
        let pointer = __swift_bridge__$Vec_Engine$get(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return EngineRef(ptr: pointer!)
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<EngineRefMut> {
        let pointer = __swift_bridge__$Vec_Engine$get_mut(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return EngineRefMut(ptr: pointer!)
        }
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<EngineRef> {
        UnsafePointer<EngineRef>(OpaquePointer(__swift_bridge__$Vec_Engine$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_Engine$len(vecPtr)
    }
}


public class FileListing: FileListingRefMut {
    var isOwned: Bool = true

    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }

    deinit {
        if isOwned {
            __swift_bridge__$FileListing$_free(ptr)
        }
    }
}
public class FileListingRefMut: FileListingRef {
    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }
}
public class FileListingRef {
    var ptr: UnsafeMutableRawPointer

    public init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }
}
extension FileListingRef {
    public func len() -> UInt {
        __swift_bridge__$FileListing$len(ptr)
    }

    public func entry(_ index: UInt) -> FileEntry {
        __swift_bridge__$FileListing$entry(ptr, index).intoSwiftRepr()
    }
}
extension FileListing: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_FileListing$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_FileListing$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: FileListing) {
        __swift_bridge__$Vec_FileListing$push(vecPtr, {value.isOwned = false; return value.ptr;}())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let pointer = __swift_bridge__$Vec_FileListing$pop(vecPtr)
        if pointer == nil {
            return nil
        } else {
            return (FileListing(ptr: pointer!) as! Self)
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<FileListingRef> {
        let pointer = __swift_bridge__$Vec_FileListing$get(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return FileListingRef(ptr: pointer!)
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<FileListingRefMut> {
        let pointer = __swift_bridge__$Vec_FileListing$get_mut(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return FileListingRefMut(ptr: pointer!)
        }
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<FileListingRef> {
        UnsafePointer<FileListingRef>(OpaquePointer(__swift_bridge__$Vec_FileListing$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_FileListing$len(vecPtr)
    }
}


public class SearchBatch: SearchBatchRefMut {
    var isOwned: Bool = true

    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }

    deinit {
        if isOwned {
            __swift_bridge__$SearchBatch$_free(ptr)
        }
    }
}
public class SearchBatchRefMut: SearchBatchRef {
    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }
}
public class SearchBatchRef {
    var ptr: UnsafeMutableRawPointer

    public init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }
}
extension SearchBatchRef {
    public func isEnd() -> Bool {
        __swift_bridge__$SearchBatch$is_end(ptr)
    }

    public func len() -> UInt {
        __swift_bridge__$SearchBatch$len(ptr)
    }

    public func entry(_ index: UInt) -> FileEntry {
        __swift_bridge__$SearchBatch$entry(ptr, index).intoSwiftRepr()
    }
}
extension SearchBatch: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_SearchBatch$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_SearchBatch$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: SearchBatch) {
        __swift_bridge__$Vec_SearchBatch$push(vecPtr, {value.isOwned = false; return value.ptr;}())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let pointer = __swift_bridge__$Vec_SearchBatch$pop(vecPtr)
        if pointer == nil {
            return nil
        } else {
            return (SearchBatch(ptr: pointer!) as! Self)
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<SearchBatchRef> {
        let pointer = __swift_bridge__$Vec_SearchBatch$get(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return SearchBatchRef(ptr: pointer!)
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<SearchBatchRefMut> {
        let pointer = __swift_bridge__$Vec_SearchBatch$get_mut(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return SearchBatchRefMut(ptr: pointer!)
        }
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<SearchBatchRef> {
        UnsafePointer<SearchBatchRef>(OpaquePointer(__swift_bridge__$Vec_SearchBatch$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_SearchBatch$len(vecPtr)
    }
}



public func ffi_index_open<GenericIntoRustString: IntoRustString>(_ root: GenericIntoRustString) -> UInt64 {
    __swift_bridge__$ffi_index_open({ let rustString = root.intoRustString(); rustString.isOwned = false; return rustString.ptr }())
}
public func ffi_index_close(_ handle: UInt64) {
    __swift_bridge__$ffi_index_close(handle)
}
public func ffi_index_query_fuzzy<GenericIntoRustString: IntoRustString>(_ handle: UInt64, _ query: GenericIntoRustString, _ limit: UInt32) -> FileHitList {
    FileHitList(ptr: __swift_bridge__$ffi_index_query_fuzzy(handle, { let rustString = query.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), limit))
}
public func ffi_index_query_symbols<GenericIntoRustString: IntoRustString>(_ handle: UInt64, _ query: GenericIntoRustString, _ limit: UInt32) -> SymbolHitList {
    SymbolHitList(ptr: __swift_bridge__$ffi_index_query_symbols(handle, { let rustString = query.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), limit))
}
public func ffi_index_query_git_dirty(_ handle: UInt64) -> FileHitList {
    FileHitList(ptr: __swift_bridge__$ffi_index_query_git_dirty(handle))
}
public struct FfiFileHit {
    public var path_rel: RustString
    public var score: UInt32

    public init(path_rel: RustString,score: UInt32) {
        self.path_rel = path_rel
        self.score = score
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$FfiFileHit {
        { let val = self; return __swift_bridge__$FfiFileHit(path_rel: { let rustString = val.path_rel.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), score: val.score); }()
    }
}
extension __swift_bridge__$FfiFileHit {
    @inline(__always)
    func intoSwiftRepr() -> FfiFileHit {
        { let val = self; return FfiFileHit(path_rel: RustString(ptr: val.path_rel), score: val.score); }()
    }
}
extension __swift_bridge__$Option$FfiFileHit {
    @inline(__always)
    func intoSwiftRepr() -> Optional<FfiFileHit> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<FfiFileHit>) -> __swift_bridge__$Option$FfiFileHit {
        if let v = val {
            return __swift_bridge__$Option$FfiFileHit(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$FfiFileHit(is_some: false, val: __swift_bridge__$FfiFileHit())
        }
    }
}
public struct FfiSymbolHit {
    public var path_rel: RustString
    public var name: RustString
    public var kind_raw: UInt8
    public var line: UInt32

    public init(path_rel: RustString,name: RustString,kind_raw: UInt8,line: UInt32) {
        self.path_rel = path_rel
        self.name = name
        self.kind_raw = kind_raw
        self.line = line
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$FfiSymbolHit {
        { let val = self; return __swift_bridge__$FfiSymbolHit(path_rel: { let rustString = val.path_rel.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), name: { let rustString = val.name.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), kind_raw: val.kind_raw, line: val.line); }()
    }
}
extension __swift_bridge__$FfiSymbolHit {
    @inline(__always)
    func intoSwiftRepr() -> FfiSymbolHit {
        { let val = self; return FfiSymbolHit(path_rel: RustString(ptr: val.path_rel), name: RustString(ptr: val.name), kind_raw: val.kind_raw, line: val.line); }()
    }
}
extension __swift_bridge__$Option$FfiSymbolHit {
    @inline(__always)
    func intoSwiftRepr() -> Optional<FfiSymbolHit> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<FfiSymbolHit>) -> __swift_bridge__$Option$FfiSymbolHit {
        if let v = val {
            return __swift_bridge__$Option$FfiSymbolHit(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$FfiSymbolHit(is_some: false, val: __swift_bridge__$FfiSymbolHit())
        }
    }
}

public class FileHitList: FileHitListRefMut {
    var isOwned: Bool = true

    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }

    deinit {
        if isOwned {
            __swift_bridge__$FileHitList$_free(ptr)
        }
    }
}
public class FileHitListRefMut: FileHitListRef {
    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }
}
public class FileHitListRef {
    var ptr: UnsafeMutableRawPointer

    public init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }
}
extension FileHitListRef {
    public func len() -> UInt {
        __swift_bridge__$FileHitList$len(ptr)
    }

    public func at(_ index: UInt) -> FfiFileHit {
        __swift_bridge__$FileHitList$at(ptr, index).intoSwiftRepr()
    }
}
extension FileHitList: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_FileHitList$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_FileHitList$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: FileHitList) {
        __swift_bridge__$Vec_FileHitList$push(vecPtr, {value.isOwned = false; return value.ptr;}())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let pointer = __swift_bridge__$Vec_FileHitList$pop(vecPtr)
        if pointer == nil {
            return nil
        } else {
            return (FileHitList(ptr: pointer!) as! Self)
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<FileHitListRef> {
        let pointer = __swift_bridge__$Vec_FileHitList$get(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return FileHitListRef(ptr: pointer!)
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<FileHitListRefMut> {
        let pointer = __swift_bridge__$Vec_FileHitList$get_mut(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return FileHitListRefMut(ptr: pointer!)
        }
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<FileHitListRef> {
        UnsafePointer<FileHitListRef>(OpaquePointer(__swift_bridge__$Vec_FileHitList$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_FileHitList$len(vecPtr)
    }
}


public class SymbolHitList: SymbolHitListRefMut {
    var isOwned: Bool = true

    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }

    deinit {
        if isOwned {
            __swift_bridge__$SymbolHitList$_free(ptr)
        }
    }
}
public class SymbolHitListRefMut: SymbolHitListRef {
    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }
}
public class SymbolHitListRef {
    var ptr: UnsafeMutableRawPointer

    public init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }
}
extension SymbolHitListRef {
    public func len() -> UInt {
        __swift_bridge__$SymbolHitList$len(ptr)
    }

    public func at(_ index: UInt) -> FfiSymbolHit {
        __swift_bridge__$SymbolHitList$at(ptr, index).intoSwiftRepr()
    }
}
extension SymbolHitList: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_SymbolHitList$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_SymbolHitList$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: SymbolHitList) {
        __swift_bridge__$Vec_SymbolHitList$push(vecPtr, {value.isOwned = false; return value.ptr;}())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let pointer = __swift_bridge__$Vec_SymbolHitList$pop(vecPtr)
        if pointer == nil {
            return nil
        } else {
            return (SymbolHitList(ptr: pointer!) as! Self)
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<SymbolHitListRef> {
        let pointer = __swift_bridge__$Vec_SymbolHitList$get(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return SymbolHitListRef(ptr: pointer!)
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<SymbolHitListRefMut> {
        let pointer = __swift_bridge__$Vec_SymbolHitList$get_mut(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return SymbolHitListRefMut(ptr: pointer!)
        }
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<SymbolHitListRef> {
        UnsafePointer<SymbolHitListRef>(OpaquePointer(__swift_bridge__$Vec_SymbolHitList$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_SymbolHitList$len(vecPtr)
    }
}



public func ffi_content_start<GenericIntoRustString: IntoRustString>(_ handle: UInt64, _ pattern: GenericIntoRustString) -> UInt64 {
    __swift_bridge__$ffi_content_start(handle, { let rustString = pattern.intoRustString(); rustString.isOwned = false; return rustString.ptr }())
}
public func ffi_content_poll(_ session: UInt64, _ max: UInt32) -> ContentHitList {
    ContentHitList(ptr: __swift_bridge__$ffi_content_poll(session, max))
}
public func ffi_content_cancel(_ session: UInt64) {
    __swift_bridge__$ffi_content_cancel(session)
}
public struct FfiContentHit {
    public var path_rel: RustString
    public var line: UInt32
    public var preview: RustString

    public init(path_rel: RustString,line: UInt32,preview: RustString) {
        self.path_rel = path_rel
        self.line = line
        self.preview = preview
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$FfiContentHit {
        { let val = self; return __swift_bridge__$FfiContentHit(path_rel: { let rustString = val.path_rel.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), line: val.line, preview: { let rustString = val.preview.intoRustString(); rustString.isOwned = false; return rustString.ptr }()); }()
    }
}
extension __swift_bridge__$FfiContentHit {
    @inline(__always)
    func intoSwiftRepr() -> FfiContentHit {
        { let val = self; return FfiContentHit(path_rel: RustString(ptr: val.path_rel), line: val.line, preview: RustString(ptr: val.preview)); }()
    }
}
extension __swift_bridge__$Option$FfiContentHit {
    @inline(__always)
    func intoSwiftRepr() -> Optional<FfiContentHit> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<FfiContentHit>) -> __swift_bridge__$Option$FfiContentHit {
        if let v = val {
            return __swift_bridge__$Option$FfiContentHit(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$FfiContentHit(is_some: false, val: __swift_bridge__$FfiContentHit())
        }
    }
}

public class ContentHitList: ContentHitListRefMut {
    var isOwned: Bool = true

    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }

    deinit {
        if isOwned {
            __swift_bridge__$ContentHitList$_free(ptr)
        }
    }
}
public class ContentHitListRefMut: ContentHitListRef {
    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }
}
public class ContentHitListRef {
    var ptr: UnsafeMutableRawPointer

    public init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }
}
extension ContentHitListRef {
    public func len() -> UInt {
        __swift_bridge__$ContentHitList$len(ptr)
    }

    public func at(_ index: UInt) -> FfiContentHit {
        __swift_bridge__$ContentHitList$at(ptr, index).intoSwiftRepr()
    }
}
extension ContentHitList: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_ContentHitList$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_ContentHitList$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: ContentHitList) {
        __swift_bridge__$Vec_ContentHitList$push(vecPtr, {value.isOwned = false; return value.ptr;}())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let pointer = __swift_bridge__$Vec_ContentHitList$pop(vecPtr)
        if pointer == nil {
            return nil
        } else {
            return (ContentHitList(ptr: pointer!) as! Self)
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<ContentHitListRef> {
        let pointer = __swift_bridge__$Vec_ContentHitList$get(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return ContentHitListRef(ptr: pointer!)
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<ContentHitListRefMut> {
        let pointer = __swift_bridge__$Vec_ContentHitList$get_mut(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return ContentHitListRefMut(ptr: pointer!)
        }
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<ContentHitListRef> {
        UnsafePointer<ContentHitListRef>(OpaquePointer(__swift_bridge__$Vec_ContentHitList$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_ContentHitList$len(vecPtr)
    }
}



public func ffi_git_snapshot<GenericIntoRustString: IntoRustString>(_ root: GenericIntoRustString) -> Optional<FfiGitSnapshot> {
    __swift_bridge__$ffi_git_snapshot({ let rustString = root.intoRustString(); rustString.isOwned = false; return rustString.ptr }()).intoSwiftRepr()
}
public func ffi_git_modified_paths<GenericIntoRustString: IntoRustString>(_ root: GenericIntoRustString) -> GitPathList {
    GitPathList(ptr: __swift_bridge__$ffi_git_modified_paths({ let rustString = root.intoRustString(); rustString.isOwned = false; return rustString.ptr }()))
}
public func ffi_git_added_paths<GenericIntoRustString: IntoRustString>(_ root: GenericIntoRustString) -> GitPathList {
    GitPathList(ptr: __swift_bridge__$ffi_git_added_paths({ let rustString = root.intoRustString(); rustString.isOwned = false; return rustString.ptr }()))
}
public func ffi_git_deleted_paths<GenericIntoRustString: IntoRustString>(_ root: GenericIntoRustString) -> GitPathList {
    GitPathList(ptr: __swift_bridge__$ffi_git_deleted_paths({ let rustString = root.intoRustString(); rustString.isOwned = false; return rustString.ptr }()))
}
public func ffi_git_untracked_paths<GenericIntoRustString: IntoRustString>(_ root: GenericIntoRustString) -> GitPathList {
    GitPathList(ptr: __swift_bridge__$ffi_git_untracked_paths({ let rustString = root.intoRustString(); rustString.isOwned = false; return rustString.ptr }()))
}
public struct FfiGitSnapshot {
    public var branch: RustString
    public var modified_count: UInt32
    public var untracked_count: UInt32
    public var added_count: UInt32
    public var deleted_count: UInt32

    public init(branch: RustString,modified_count: UInt32,untracked_count: UInt32,added_count: UInt32,deleted_count: UInt32) {
        self.branch = branch
        self.modified_count = modified_count
        self.untracked_count = untracked_count
        self.added_count = added_count
        self.deleted_count = deleted_count
    }

    @inline(__always)
    func intoFfiRepr() -> __swift_bridge__$FfiGitSnapshot {
        { let val = self; return __swift_bridge__$FfiGitSnapshot(branch: { let rustString = val.branch.intoRustString(); rustString.isOwned = false; return rustString.ptr }(), modified_count: val.modified_count, untracked_count: val.untracked_count, added_count: val.added_count, deleted_count: val.deleted_count); }()
    }
}
extension __swift_bridge__$FfiGitSnapshot {
    @inline(__always)
    func intoSwiftRepr() -> FfiGitSnapshot {
        { let val = self; return FfiGitSnapshot(branch: RustString(ptr: val.branch), modified_count: val.modified_count, untracked_count: val.untracked_count, added_count: val.added_count, deleted_count: val.deleted_count); }()
    }
}
extension __swift_bridge__$Option$FfiGitSnapshot {
    @inline(__always)
    func intoSwiftRepr() -> Optional<FfiGitSnapshot> {
        if self.is_some {
            return self.val.intoSwiftRepr()
        } else {
            return nil
        }
    }

    @inline(__always)
    static func fromSwiftRepr(_ val: Optional<FfiGitSnapshot>) -> __swift_bridge__$Option$FfiGitSnapshot {
        if let v = val {
            return __swift_bridge__$Option$FfiGitSnapshot(is_some: true, val: v.intoFfiRepr())
        } else {
            return __swift_bridge__$Option$FfiGitSnapshot(is_some: false, val: __swift_bridge__$FfiGitSnapshot())
        }
    }
}

public class GitPathList: GitPathListRefMut {
    var isOwned: Bool = true

    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }

    deinit {
        if isOwned {
            __swift_bridge__$GitPathList$_free(ptr)
        }
    }
}
public class GitPathListRefMut: GitPathListRef {
    public override init(ptr: UnsafeMutableRawPointer) {
        super.init(ptr: ptr)
    }
}
public class GitPathListRef {
    var ptr: UnsafeMutableRawPointer

    public init(ptr: UnsafeMutableRawPointer) {
        self.ptr = ptr
    }
}
extension GitPathListRef {
    public func len() -> UInt {
        __swift_bridge__$GitPathList$len(ptr)
    }

    public func at(_ index: UInt) -> RustString {
        RustString(ptr: __swift_bridge__$GitPathList$at(ptr, index))
    }
}
extension GitPathList: Vectorizable {
    public static func vecOfSelfNew() -> UnsafeMutableRawPointer {
        __swift_bridge__$Vec_GitPathList$new()
    }

    public static func vecOfSelfFree(vecPtr: UnsafeMutableRawPointer) {
        __swift_bridge__$Vec_GitPathList$drop(vecPtr)
    }

    public static func vecOfSelfPush(vecPtr: UnsafeMutableRawPointer, value: GitPathList) {
        __swift_bridge__$Vec_GitPathList$push(vecPtr, {value.isOwned = false; return value.ptr;}())
    }

    public static func vecOfSelfPop(vecPtr: UnsafeMutableRawPointer) -> Optional<Self> {
        let pointer = __swift_bridge__$Vec_GitPathList$pop(vecPtr)
        if pointer == nil {
            return nil
        } else {
            return (GitPathList(ptr: pointer!) as! Self)
        }
    }

    public static func vecOfSelfGet(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<GitPathListRef> {
        let pointer = __swift_bridge__$Vec_GitPathList$get(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return GitPathListRef(ptr: pointer!)
        }
    }

    public static func vecOfSelfGetMut(vecPtr: UnsafeMutableRawPointer, index: UInt) -> Optional<GitPathListRefMut> {
        let pointer = __swift_bridge__$Vec_GitPathList$get_mut(vecPtr, index)
        if pointer == nil {
            return nil
        } else {
            return GitPathListRefMut(ptr: pointer!)
        }
    }

    public static func vecOfSelfAsPtr(vecPtr: UnsafeMutableRawPointer) -> UnsafePointer<GitPathListRef> {
        UnsafePointer<GitPathListRef>(OpaquePointer(__swift_bridge__$Vec_GitPathList$as_ptr(vecPtr)))
    }

    public static func vecOfSelfLen(vecPtr: UnsafeMutableRawPointer) -> UInt {
        __swift_bridge__$Vec_GitPathList$len(vecPtr)
    }
}



