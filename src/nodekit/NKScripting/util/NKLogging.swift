/*
 * nodekit.io
 *
 * Copyright (c) 2016 OffGrid Networks. All Rights Reserved.
 * Portions Copyright 2015 XWebView
 * Portions Copyright (c) 2014 Intel Corporation.  All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Darwin

import Foundation

public typealias asl_object_t = COpaquePointer

@_silgen_name("asl_open") func asl_open(ident: UnsafePointer<Int8>, _ facility: UnsafePointer<Int8>, _ opts: UInt32) -> asl_object_t

@_silgen_name("asl_close") func asl_close(obj: asl_object_t)

@_silgen_name("asl_vlog") func asl_vlog(obj: asl_object_t, _ msg: asl_object_t, _ level: Int32, _ format: UnsafePointer<Int8>, _ ap: CVaListPointer) -> Int32

@_silgen_name("asl_add_output_file") func asl_add_output_file(client: asl_object_t, _ descriptor: Int32, _ msg_fmt: UnsafePointer<Int8>, _ time_fmt: UnsafePointer<Int8>, _ filter: Int32, _ text_encoding: Int32) -> Int32

@_silgen_name("asl_set_output_file_filter") func asl_set_output_file_filter(asl: asl_object_t, _ descriptor: Int32, _ filter: Int32) -> Int32

public class NKLogging {
    
    private static var logger = NKLogging(facility: "io.nodekit.core.consolelog", emitter: NKEventEmitter.global)
    
    public class func log(message: String, level: Level? = nil, labels: [String:AnyObject]? = [:]) {
        
        
       logger.log(message, level: level, labels: labels)
        
        print(message)
        
    }
    
    @noreturn public class func die(@autoclosure message: ()->String, file: StaticString = #file, line: UInt = #line) {
        
        logger.log(message(), level: .Alert)
        
        fatalError(message, file: file, line: line)
        
    }
    
    public enum Level: Int32 {
        
        case Emergency = 0
        
        case Alert     = 1
        
        case Critical  = 2
        
        case Error     = 3
        
        case Warning   = 4
        
        case Notice    = 5
        
        case Info      = 6
        
        case Debug     = 7
        
        private static let symbols: [Character] = [
            
            "\0", "\0", "$", "!", "?", "-", "+", " "
            
        ]
        
        public init(description: String) {
            self = .Debug
            var i: Int32 = 0
            while let item = Level(rawValue: i) {
                if String(item) == description { self = item }
                i += 1
            }
        }
        
        private init?(symbol: Character) {
            
            guard symbol != "\0", let value = Level.symbols.indexOf(symbol) else {
                
                return nil
                
            }
              
            self = Level(rawValue: Int32(value))!
            
        }
        
    }
    
    public struct Filter: OptionSetType {
        
        private var value: Int32
        
        public var rawValue: Int32 {
            
            return value
            
        }
        
        public init(rawValue: Int32) {
            
            self.value = rawValue
            
        }
        
        public init(mask: Level) {
            
            self.init(rawValue: 1 << mask.rawValue)
            
        }
        
        public init(upto: Level) {
            
            self.init(rawValue: 1 << (upto.rawValue + 1) - 1)
            
        }
        
        public init(filter: Level...) {
            
            self.init(rawValue: filter.reduce(0) { $0 | $1.rawValue })
            
        }
        
    }
    
    public struct Entry {
        
        public let message: String
        
        public let level: Level
        
        public let labels: [String: AnyObject]
        
        public let timestamp: NSDate
        
    }
    
    public var filter: Filter {
        
        didSet {
            
            asl_set_output_file_filter(client, STDERR_FILENO, filter.rawValue)
            
        }
        
    }
    
    private let client: asl_object_t
    
    private var lock: pthread_mutex_t = pthread_mutex_t()
    
    private var emitters: [NKEventEmitter] = []
    
    public init(facility: String, format: String? = nil, emitter: NKEventEmitter?) {
        
        client = asl_open(nil, facility, 0)
        
        pthread_mutex_init(&lock, nil)
        
        #if DEBUG
            
            filter = Filter(upto: .Debug)
            
        #else
            
            filter = Filter(upto: .Notice)
            
        #endif
        
        let format = format ?? "$((Time)(lcl)) $(Facility) <$((Level)(char))>: $(Message)"
        
        asl_add_output_file(client, STDERR_FILENO, format, "sec", filter.rawValue, 1)
        
        if let emitter = emitter {
            self.addEmitter(emitter)
        }
        
    }
    
    public func addEmitter(emitter: NKEventEmitter) {
        emitters.append(emitter)
    }
    
    public func removeEmitter(emitter: NKEventEmitter) {
        emitters = emitters.filter() { $0 !== emitter }
    }
    
    deinit {
        
        asl_close(client)
        
        pthread_mutex_destroy(&lock)
        
    }
    
    public func log(message: String, level: Level, labels: [String:AnyObject]) {
        
        pthread_mutex_lock(&lock)
        
        asl_vlog(client, nil, level.rawValue, message, getVaList([]))
        
        emitters.forEach { (emitter) in
            emitter.emit("log", Entry(message: message, level: level, labels: labels, timestamp: NSDate()) )
        }
        
        pthread_mutex_unlock(&lock)
        
    }
    
    public func log(message: String, level: Level? = nil, labels: [String:AnyObject]? = nil) {
                
        var msg = message
        
        var lvl = level ?? .Debug
        
        let labels = labels ?? [:]
        
        if level == nil, let ch = msg.characters.first, l = Level(symbol: ch) {
            
            msg = msg[msg.startIndex.successor() ..< msg.endIndex]
            
            lvl = l
            
        }
 
        log(msg, level: lvl, labels: labels)
        
    }
    
}


