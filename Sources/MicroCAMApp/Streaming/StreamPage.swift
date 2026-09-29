import MicroCAMCore

enum StreamPage {
    static func html(mode: StreamMode, embedded: Bool) -> String {
        #"<!doctype html><meta charset="utf-8"><title>microCAM</title><body style="margin:0;background:#000"><img src="/stream" style="width:100vw;height:100vh;object-fit:contain">"#
    }
}
