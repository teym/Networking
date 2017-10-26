//
//  Networking.swift
//  Networking
//
//  Created by 王航 on 2017/10/24.
//  Copyright © 2017年 mike. All rights reserved.
//

import Foundation
import Interfaces
import SwiftHTTP
import SystemConfiguration

func callback(reachability:SCNetworkReachability, flags: SCNetworkReachabilityFlags, info: UnsafeMutableRawPointer?) {
    guard let info = info else { return }
    let reach = Unmanaged<Reachability>.fromOpaque(info).takeUnretainedValue()
    reach.onChange()
}
class Reachability:NSObject {
    var reachabilityType:ReachabilityType = .notReachable
    let reachabilityRef:SCNetworkReachability
    var observer:(ReachabilityType)->Void
    init?(host:String) {
        observer = {_ in}
        if let reachabilityRef = SCNetworkReachabilityCreateWithName(nil, host) {
            self.reachabilityRef = reachabilityRef
        }else{
            return nil
        }
        super.init()
        var context = SCNetworkReachabilityContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        context.info = UnsafeMutableRawPointer(Unmanaged<Reachability>.passUnretained(self).toOpaque())
        if !SCNetworkReachabilitySetCallback(reachabilityRef, callback, &context) {
            return nil
        }
        
        if !SCNetworkReachabilitySetDispatchQueue(reachabilityRef, DispatchQueue.global()) {
            SCNetworkReachabilitySetCallback(reachabilityRef, nil, nil)
            return nil
        }
    }
    func on(handle:@escaping (ReachabilityType)->Void){
        self.observer = handle
        let cur = reachabilityType
        DispatchQueue.main.async {
            handle(cur)
        }
    }
    func onChange() {
        var flag = SCNetworkReachabilityFlags()
        if SCNetworkReachabilityGetFlags(reachabilityRef, &flag) {
            let pre = reachabilityType
            if flag.contains(.connectionRequired) || flag.contains(.transientConnection) {
                reachabilityType = .notReachable
            }else if flag.contains(.reachable) {
                reachabilityType = flag.contains(.isWWAN) ? .reachableWWAN : .reachableWiFi
            }
            if pre != reachabilityType {
                let handle = self.observer
                let cur = reachabilityType
                DispatchQueue.main.async {
                    handle(cur)
                }
            }
        }
    }
    deinit {
        SCNetworkReachabilitySetCallback(reachabilityRef, nil, nil)
        SCNetworkReachabilitySetDispatchQueue(reachabilityRef, nil)
    }
}

class TaskResponse:NSObject,NetworkResponse{
    var headers: [String : String]?
    var mimeType: String?
    var data: Data
    var statusCode: Int
    var URL: URL?
    var error: Error?
    
    init(response:Response){
        self.headers = response.headers
        self.mimeType = response.mimeType
        self.data = response.data
        self.statusCode = response.statusCode ?? 0
        self.URL = response.URL
        self.error = response.error
    }
}

class TaskItem:NSObject,NetworkTask {
    var task:HTTP? = nil
    var response:Response? = nil
    var finished:Bool = false
    let middleHook:(NetworkResponse)->Void
    var success:(Data,NetworkResponse)->Void
    var failure:(Error?,NetworkResponse?)->Void
    init(task:()->HTTP?, middleHook:@escaping (NetworkResponse)->Void) {
        self.middleHook = middleHook
        self.success = {(_,_) in}
        self.failure = {(_,_) in}
        super.init()
        if let t = task() {
            self.task = t
            t.run(self.on)
        }else{
            self.finished = true
        }
    }
    private func on(response:Response) {
        guard !self.finished else {return}
        self.finished = true
        self.response = response
        self.invoke(success: self.success, failure: self.failure)
    }
    private func invoke(success:(Data,NetworkResponse)->Void,failure:(Error?,NetworkResponse?)->Void){
        if let resp = self.response {
            if (200 ..< 300).contains(resp.statusCode ?? 0) {
                DispatchQueue.main.async {
                    success(resp.data,TaskResponse(response: resp))
                }
            }else {
                DispatchQueue.main.async {
                    failure(resp.error,TaskResponse(response: resp))
                }
            }
        }else{
            DispatchQueue.main.async {
                failure(nil,nil)
            }
        }
    }
    private func setHandles(success:@escaping (Data,NetworkResponse)->Void,failure:@escaping (Error?,NetworkResponse?)->Void) {
        guard !self.finished else {
            return self.invoke(success: success, failure: failure)
        }
        self.success = success
        self.failure = failure
    }
    func response(success:@escaping (Data,NetworkResponse)->Void, failure:@escaping (Error?,NetworkResponse?)->Void) -> NetworkTask {
        self.setHandles(success: {(d,r) in success(d,r)}, failure: {(e,r) in failure(e,r)})
        return self
    }
    func responseJSON(success:@escaping (Any,NetworkResponse)->Void, failure:@escaping (Error?,NetworkResponse?)->Void) -> NetworkTask {
        self.setHandles(success: { (d, r) in
            do {
                let json = try JSONSerialization.jsonObject(with: d, options: .init(rawValue: 0))
                success(json,r)
            }catch (let e){
                failure(e,r)
            }
        }, failure: {(e, r) in
            failure(e,r)
        })
        return self
    }
    func progress(block:@escaping(Float)->Void) -> NetworkTask {
        guard !self.finished && self.task != nil else {
            DispatchQueue.main.async {
                block(1.0)
            }
            return self
        }
        self.task?.progress = {(p)->Void in
            DispatchQueue.main.async {
                block(p)
            }
        }
        return self
    }
}

class NetObserve:NSObject {
    struct Context {
        static var KEY = "ObserveContextKey"
    }
    let object:NSObject
    let keyPath:String
    var handle:((Any)->Void)?
    init(object:NSObject,keyPath:String) {
        self.object = object
        self.keyPath = keyPath
        super.init()
        object.addObserver(self, forKeyPath: keyPath, options: .new, context: &Context.KEY)
    }
    deinit {
        object.removeObserver(self, forKeyPath: keyPath, context: &Context.KEY)
    }
    func on<T>(handle:@escaping (T)->Void) {
        self.handle = {(val:Any)->Void in
            if let valT = val as? T {
                handle(valT)
            }
        }
    }
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if (keyPath.map({$0 == self.keyPath }) ?? false) &&
            ((object as? NSObject).map({$0 === self.object}) ?? false) &&
            (context.map({$0 == &Context.KEY}) ?? false) {
            if let val = change?[NSKeyValueChangeKey.newKey] {
                self.handle?(val)
            }
        }else{
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
}

class Networking:NSObject, Module, Network {
    static func interfaces() -> [AnyObject] {
        return [Network.self as AnyObject]
    }
    static func loadOnStart() -> Bool {
        return false
    }
    required init(inject: ModuleInject) {
        self.handle = {(_:NetworkResponse)->Void in}
        super.init()
        if let user:UserAuth = (try? ModuleInjectT(inject).instance()) {
            if let observe = (user as? NSObject).map({NetObserve(object:$0 ,keyPath:"token")}) {
                observe.on{[weak self](val:String?) -> Void in
                    self?.bearToken = val
                    print("[Network] token changed")
                }
                self.tokenObserve = observe
            }
            self.bearToken = user.token
            self.handle = {(response:NetworkResponse)->Void in
                if response.statusCode == 401 {
                    user.refresh()
                }
            }
        }
        self.reachabilityMgr = Reachability(host: "www.baidu.com")
        self.reachabilityMgr?.on(handle: {[weak self] (type) in
            self?.reachability = type
        })
    }
    
    var requestMap:Network.URLMap? = nil
    var bearToken:String? = nil
    var tokenObserve:NetObserve? = nil
    @objc dynamic var reachability:ReachabilityType = .notReachable
    var reachabilityMgr:Reachability? = nil
    var handle:(NetworkResponse)->Void
    
    func request(url:String, method:String, parameters:Any?, headers:[String:String]?) -> NetworkTask {
        var allHeaders:[String : String] = (bearToken == nil) ? [:] : ["Authorization":"Bearer \(bearToken!)"]
        allHeaders.merge(headers ?? [:]) { (_, last) -> String in last}
        allHeaders = allHeaders.filter { (kv) -> Bool in return !kv.1.isEmpty }
        let httpMethod = HTTPVerb.init(rawValue: method.uppercased()) ?? .GET
        let realURL = requestMap.map({$0(url,httpMethod.rawValue)}) ?? url
        let encoding = {(method:HTTPVerb)->HTTPSerializeProtocol in
            switch method {
            case .GET:
                return HTTPParameterSerializer()
            default:
                return JSONParameterSerializer()
            }
        }(httpMethod)
        return TaskItem(task: { () -> HTTP? in
            var params:HTTPParameterProtocol? = nil
            if let arr = parameters as? [Any] {
                params = arr
            }else if let dic = parameters as? [String:Any] {
                params = dic
            }else if parameters == nil {
                
            }else {
                print("[Network] \(method):\(url) can't serializer parameters",parameters!)
            }
            return HTTP.New(realURL, method: httpMethod, parameters: params, headers: allHeaders, requestSerializer: encoding, completionHandler: nil)
        }, middleHook: self.handle)
    }
    func upload(url:String,files:[String:AnyObject], headers:[String:String]?) -> NetworkTask {
        var allHeaders:[String : String] = (bearToken == nil) ? [:] : ["Authorization":"Bearer \(bearToken!)"]
        allHeaders.merge(headers ?? [:]) { (_, last) -> String in last}
        allHeaders = allHeaders.filter { (kv) -> Bool in return !kv.1.isEmpty }
        let realURL = requestMap.map({$0(url,HTTPVerb.POST.rawValue)}) ?? url
        
        var uploads = [String:Any]()
        for (k,v) in files {
            if let url = v as? URL {
                uploads[k] = Upload(fileUrl: url)
            }else if let data = v as? Data {
                uploads[k] = Upload(data: data, fileName: k, mimeType: "")
            }
        }
        return TaskItem(task: { () -> HTTP? in
            HTTP.New(realURL, method: .POST, parameters: uploads, headers: allHeaders, requestSerializer: HTTPParameterSerializer(), completionHandler: nil)
        }, middleHook: self.handle)
    }
}
