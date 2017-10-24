//
//  NetworkingTests.swift
//  NetworkingTests
//
//  Created by 王航 on 2017/10/24.
//  Copyright © 2017年 mike. All rights reserved.
//

import XCTest
import Interfaces
@testable import Networking

class MockUserAuth:NSObject, UserAuth {
    var pid: String?
    var uid: String?
    @objc dynamic var token: String?
    func refresh() {
        
    }
    func invalidate() {
        
    }
}
class MockInject: ModuleInject {
    let mockUser = MockUserAuth()
    func instance(interface: AnyObject) throws -> AnyObject {
        guard let target = (interface as? Protocol).map({NSStringFromProtocol($0)}) else {
            throw ModuleInjectError.ModuleNotFound(msg: "nothing")
        }
        if target == NSStringFromProtocol(UserAuth.self as Protocol) {
            return self.mockUser
        }
        throw ModuleInjectError.ModuleNotFound(msg: target)
    }
}

class NetworkingTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        let network = Networking(inject: MockInject())
        let exp = self.expectation(description: "request")
        network.request(url: "https://www.baidu.com", method: "get", parameters: nil, headers: nil).response(success: { (d,r) in
            exp.fulfill()
            XCTAssert(r.statusCode == 200, "get Error")
        }) { (err,r) in
            exp.fulfill()
            XCTAssert(false)
        }
        self.waitForExpectations(timeout: 10) { (e) in
            XCTAssert(exp.assertForOverFulfill,"timeout")
        }
    }
    func testObserve() {
        class TestObj:NSObject{
            @objc dynamic var str = "123"
        }
        let obj = TestObj()
        let exp = self.expectation(description: "observe")
        var obs:NetObserve? = NetObserve(object: obj, keyPath: "str")
        obs!.on { (val:String) in
            exp.fulfill()
            XCTAssert(val == obj.str)
        }
        obj.str = "456"
        self.waitForExpectations(timeout: 1) { (err) in
            XCTAssert(exp.assertForOverFulfill,"fail")
        }
        
        obs = nil
        obj.str = "789"
        XCTAssert(exp.expectedFulfillmentCount == 1,"fail")
    }
    
    func testToken() {
        let inject = MockInject()
        let user:UserAuth = try! ModuleInjectT(inject).instance()
        let mockUser = user as! MockUserAuth
        let network = Networking(inject: inject)
        XCTAssert(user.token == nil)
        XCTAssert(network.bearToken == nil)
        mockUser.token = "abcdes"
        XCTAssert(network.bearToken == mockUser.token)
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
}
