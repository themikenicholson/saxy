//
//  OXPathMapper.m
//  SAXy OX - Object-to-XML mapping library
//
//  Created by Richard Easterling on 1/28/13.
//

#import "OXPathMapper.h"
#import "OXComplexMapper.h"
#import "OXContext.h"
#import "OXUtil.h"
#import "OXProperty.h"

#pragma mark - OXPathMapper


@implementation OXPathMapper

#pragma mark - constructors

- (id)initMapperWithEnum:(OXMapperEnum)mapperEnum
{
    if (self = [super init]) {
        _mapperEnum = mapperEnum;
    }
    return self;
}

- (id)init
{
    return [self initMapperWithEnum:OX_PATH_MAPPER];
}

- (id)initMapperToType:(OXType *)toType toPath:(NSString *)toPath fromType:(OXType *)fromType fromPath:(NSString *)fromPath
{
    if (self = [self init]) {
        _toType = toType;
        _toPath = toPath;
        _fromType = fromType;
        _fromPath = fromPath;
    }
    return self;
}

- (id)initMapperToClass:(Class)toType toPath:(NSString *)toPath fromClass:(Class)fromType fromPath:(NSString *)fromPath
{
    if (self = [self init]) {
        _toType = [OXType cachedType:toType];
        _toPath = toPath;
        _fromType = [OXType cachedType:fromType];
        _fromPath = fromPath;  
    }
    return self;
}

- (id)initMapperToClass:(Class)toType toPath:(NSString *)toPath fromScalar:(const char *)fromEncodedType fromPath:(NSString *)fromPath
{
    if (self = [self init]) {
        _toType = [OXType cachedType:toType];
        _toPath = toPath;
        _fromType = [OXType cachedScalarType:fromEncodedType];
        _fromPath = fromPath;
    }
    return self;
}

- (id)initMapperToScalar:(const char *)toEncodedType toPath:(NSString *)toPath fromClass:(Class)fromType fromPath:(NSString *)fromPath
{
    if (self = [self init]) {
        _toType = [OXType cachedScalarType:toEncodedType];
        _toPath = toPath;
        _fromType = [OXType cachedType:fromType];
        _fromPath = fromPath;
    }
    return self;
}

#pragma mark - properties

@dynamic toPathRoot;
- (NSString *)toPathRoot
{
    return [OXUtil firstSegmentFromPath:_toPath separator:'.'];         //assume KVC dot-separators
}

@dynamic fromPathRoot;
- (NSString *)fromPathRoot
{
    return [OXUtil firstSegmentFromPath:_fromPath separator:'.'];       //assume KVC dot-separators
}

@dynamic toPathLeaf;
- (NSString *)toPathLeaf
{
    return [OXUtil lastSegmentFromPath:_toPath separator:'.'];          //assume KVC dot-separators
}

@dynamic fromPathLeaf;
- (NSString *)fromPathLeaf
{
    return [OXUtil lastSegmentFromPath:_fromPath separator:'.'];        //assume KVC dot-separators
}

#pragma mark - public


- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ %@ <- %@", NSStringFromClass(_toType.type), _toPath, _fromPath];
}

- (void)assignDefaultBlocks:(OXContext *)context
{
    BOOL isComplexKVC = [_toPath rangeOfString:@"."].location != NSNotFound;
    if (!_factory) {
        _factory = ^(NSString *path, OXContext *ctx) {
            OXPathMapper *mapper = ctx.currentMapper;
            return [[mapper.toType.type alloc] init];
        };
    }
//    if ([_toPath isEqualToString:@"address"])
//        NSLog(@"address");
    switch (self.toType.typeEnum) {
        case OX_CONTAINER: {
            //OXContainerType *containterType = (OXContainerType *)self.toType;
            if ( ! self.appender)
                self.appender = [context.transform appenderForContainer:self.toType.type];
            if ( ! self.enumerator)
                self.enumerator = [context.transform enumerationForContainer:self.toType.type];
            if ( ! _getter) {
                if (isComplexKVC) {
                    _getter = ^(NSString *key, id target, OXContext *ctx) {
                        return [target valueForKeyPath:key];   //call KVC getter
                    };
                } else {
                    _getter = ^(NSString *key, id target, OXContext *ctx) {
                        return [target valueForKey:key];   //call KVC getter
                    };
                }
            }
            if ( ! _setter) {
                if (isComplexKVC) {
                    _setter = ^(NSString *key, id value, id target, OXContext *ctx) {
                        [target setValue:value forKeyPath: key];  //set using KVC
                    };
                } else {
                    _setter = ^(NSString *key, id value, id target, OXContext *ctx) {
                        [target setValue:value forKey: key];  //set using KVC
                    };
                }
            }
            break;
        }
        case OX_SCALAR: {
            if ( ! self.toTransform && _fromType) {
                self.toTransform = [context.transform transformerFrom:_fromType.type toScalar:self.toType.scalarEncoding];     //_fromType.type is usualy a NSString
            }
            if ( ! self.fromTransform && _fromType) {
                self.fromTransform = [context.transform transformerScalar:_toType.scalarEncoding to:_fromType.type];
            }
            if (!self.toTransform && !self.setter)
                NSAssert2(NO, @"ERROR: missing required toTransform for %@->%@ scalar mapping", _fromType, _toType);
            if (!self.fromTransform && !self.getter)
                NSAssert1(NO, @"ERROR: missing required fromTransform for %@->NSString scalar mapping", _toType);
        }   //fall-through to OX_ATOMIC
        case OX_COMPLEX:
        case OX_ATOMIC: {
            if ( ! self.toTransform && _fromType)
                self.toTransform = [context.transform transformerFrom:_fromType.type to:_toType.type];
            if ( ! self.fromTransform && _fromType)
                self.fromTransform = [context.transform transformerFrom:_toType.type to:_fromType.type];
            //setter method
            if ( ! _setter) {
                if (isComplexKVC) {
                    if (self.toTransform) {   // is there a string->object converter?
                        _setter = ^(NSString *key, id value, id target, OXContext *ctx) {
                            OXPathMapper *mapper = ctx.currentMapper;
                            id obj = mapper.toTransform(value, ctx); //convert string->object
                            [target setValue:obj forKeyPath:key];  //set using KVC
                        };
                    } else {
                        _setter = ^(NSString *key, id value, id target, OXContext *ctx) {
                            [target setValue:value forKeyPath:key];  //set using KVC
                        };
                    }
                } else {
                    if (self.toTransform) {   // is there a string->object converter?
                        _setter = ^(NSString *key, id value, id target, OXContext *ctx) {
                            OXPathMapper *mapper = ctx.currentMapper;
                            id obj = mapper.toTransform(value, ctx); //convert string->object
                            [target setValue:obj forKey:key];  //set using KVC
                        };
                    } else {
                        _setter = ^(NSString *key, id value, id target, OXContext *ctx) {
                            [target setValue:value forKey:key];  //set using KVC
                        };
                    }
                }
            }
            //getter method
            if ( ! _getter) {
                if (isComplexKVC) {
                    if (self.fromTransform) {   // is there a object->string converter?
                        _getter = ^(NSString *key, id target, OXContext *ctx) {
                            id value = [target valueForKeyPath:key];
                            OXPathMapper *mapper = ctx.currentMapper;
                            return value==nil ? nil : mapper.fromTransform(value, ctx);
                        };
                    } else {
                        _getter = ^(NSString *key, id target, OXContext *ctx) {
                            return [target valueForKeyPath:key];   //call KVC getter
                        };
                    }
                } else {
                    if (self.fromTransform) {   // is there a object->string converter?
                        _getter = ^(NSString *key, id target, OXContext *ctx) {
                            id value = [target valueForKey:key];
                            OXPathMapper *mapper = ctx.currentMapper;
                            return value==nil ? nil : mapper.fromTransform(value, ctx);
                        };
                    } else {
                        _getter = ^(NSString *key, id target, OXContext *ctx) {
                            return [target valueForKey:key];   //call KVC getter
                        };
                    }
                }
            }
            break;
        }
        default:
            NSAssert3(NO, @"ERROR: unknown toType.typeEnum: %d for %@->%@ scalar mapping", self.toType.typeEnum, _fromType, _toType);
            break;
    }
}

- (NSArray *)addErrorMessage:(NSString *)errorMessage errors:(NSArray *)errors
{
    NSError *error = [NSError errorWithDomain:@"com.outsourcecafe.ox" code:99 userInfo:@{NSLocalizedDescriptionKey:errorMessage}];
    if (errors == nil)
        errors = [NSMutableArray array];
    if ([errors isKindOfClass:[NSMutableArray class]]) {
        [((NSMutableArray *)errors) addObject:error];
    } else {
        errors = [errors arrayByAddingObject:error];
    }
    return errors;
}

- (NSArray *)verifyToTypeUsingSelfReflection:(OXContext *)context errors:(NSArray *)errors
{
    if (_parent.toType) {               //no parent, no properties
        if (!self.virtualProperty) {    //virtual? skip type checking, because this is not a real property
            OXProperty *toProperty = [_parent.toType.properties objectForKey:self.toPathRoot];  //look up poperty metadata
            if (toProperty == nil)
                errors = [self addErrorMessage:[NSString stringWithFormat:@"no %@.%@ property found in %@ -> %@ mapping", NSStringFromClass(_parent.toType.type), self.toPathRoot, _fromPath, _toPath] errors:errors];
            Class actualToClass = toProperty.type.type;                                 //grab type from property
            BOOL isComplexKVC = [_toPath rangeOfString:@"."].location != NSNotFound;    //is this a key path?
            if (isComplexKVC) {
                if (!_toType && !_toType.type) {    //key path special case - require explicit type declarations
                    //TODO this could be fixed by following KVC property chain to discover leaf class
                    errors = [self addErrorMessage:[NSString stringWithFormat:@"complex KVC property mappings require explicit type or scalar specification -> %@ mapping", self] errors:errors];
                }
            } else if (_toType && _toType.type) {
                if ( ! [actualToClass isEqual:_toType.type] ) {
                    if ([_toType.type isSubclassOfClass:actualToClass]) {
                        if ( ! [_parent.toType.type isSubclassOfClass:[OXContext class]] ) //normal for document result object
                            NSLog(@"WARNING: %@.%@ property in  %@ -> %@ mapping is polymorphic %@ to %@", NSStringFromClass(_parent.toType.type), self.toPathRoot, _fromPath, _toPath, NSStringFromClass(actualToClass), NSStringFromClass(_toType.type));
                    } else {
                        errors = [self addErrorMessage:[NSString stringWithFormat:@"property class conflict %@ != %@ in %@ -> %@ mapping", NSStringFromClass(actualToClass), NSStringFromClass(_parent.toType.type), _fromPath, _toPath] errors:errors];
                    }
                }
            } else if (_toType) {   //_toType.type == nil, check for other attributes before overwriting with property type
                if (_toType.containerChildType) {
                    _toType.type = actualToClass;    
                    _toType.typeEnum = OX_CONTAINER;
                }
                if (_toType.scalarEncoding) {
                    _toType.type = actualToClass;
                    _toType.typeEnum = OX_SCALAR;
                }
            } else {
                _toType = toProperty.type;
            }
        }
        if (_toPath == nil) {
            errors = [self addErrorMessage:[NSString stringWithFormat:@"no 'toPath' in %@.%@ property for %@ -> %@ mapping", NSStringFromClass(_parent.toType.type), self.toPathRoot, _fromPath, _toPath] errors:errors];
        }
    }
    return errors;
}


- (NSArray *)configure:(OXContext *)context
{
    if (context == nil)
        NSAssert1(NO, @"ERROR: invalid nil context parameter in 'configure:(OXContext *)' method call on mapper: %@", self);
    NSArray *errors = nil;
    if (!_isConfigured) {
        NSAssert(context.transform != nil, @"context.transform != nil");
        errors = [self verifyToTypeUsingSelfReflection:context errors:errors];
        if (!errors) {
            [self assignDefaultBlocks:context];
            _isConfigured = YES;
        }
    }
    return errors;
}

@end

//
//  Copyright (c) 2013 Outsource Cafe, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

