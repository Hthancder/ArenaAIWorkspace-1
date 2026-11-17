#import "SBLLM.h"
#import "SBConfig.h"
#import "SBHistory.h"

#define SBLog(fmt, ...) NSLog(@"[SiriBridge] " fmt, ##__VA_ARGS__)

#pragma mark - JSON helpers

static id SBJSONObject(NSString *s) {
    if (!s.length) return nil;
    NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
    return [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
}

static NSString *SBJSONString(id obj) {
    if (!obj) return nil;
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:NULL];
    return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil;
}

static id SBValueAtPath(id root, NSString *path) {
    if (!path.length) return root;
    id cur = root;
    for (NSString *part in [path componentsSeparatedByString:@"."]) {
        if ([cur isKindOfClass:[NSArray class]]) {
            NSInteger idx = part.integerValue;
            if (idx < 0 || idx >= (NSInteger)[cur count]) return nil;
            cur = cur[idx];
        } else if ([cur isKindOfClass:[NSDictionary class]]) {
            cur = cur[part];
        } else {
            return nil;
        }
        if (!cur) return nil;
    }
    return cur;
}

static NSString *SBJSONEscape(NSString *s) {
    NSMutableString *o = [NSMutableString stringWithCapacity:s.length + 8];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        switch (c) {
            case '"':  [o appendString:@"\\\""]; break;
            case '\\': [o appendString:@"\\\\"]; break;
            case '\n': [o appendString:@"\\n"]; break;
            case '\r': [o appendString:@"\\r"]; break;
            case '\t': [o appendString:@"\\t"]; break;
            default:
                if (c < 0x20) [o appendFormat:@"\\u%04x", c];
                else [o appendFormat:@"%C", c];
        }
    }
    return o;
}

#pragma mark - SBLLM

@implementation SBLLM

+ (NSMutableURLRequest *)requestForEndpoint:(NSString *)endpoint
                                     apiKey:(NSString *)apiKey
                               extraHeaders:(NSString *)headersJSON
                                       body:(NSData *)body
                                    timeout:(NSTimeInterval)timeout {
    NSURL *url = [NSURL URLWithString:endpoint];
    if (!url) return nil;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = MAX(5, timeout);
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    if (apiKey.length) {
        [req setValue:[@"Bearer " stringByAppendingString:apiKey] forHTTPHeaderField:@"Authorization"];
        // Gemini native API dùng header riêng; gửi kèm để endpoint tự chọn
        [req setValue:apiKey forHTTPHeaderField:@"x-api-key"];
        [req setValue:apiKey forHTTPHeaderField:@"x-goog-api-key"];
    }
    NSDictionary *extra = SBJSONObject(headersJSON);
    if ([extra isKindOfClass:[NSDictionary class]]) {
        for (NSString *k in extra) {
            NSString *v = extra[k];
            if ([v isKindOfClass:[NSString class]]) [req setValue:v forHTTPHeaderField:k];
        }
    }
    req.HTTPBody = body;
    return req;
}

/// Dựng JSON body. Nếu người dùng đặt BodyTemplate thì thay placeholder;
/// ngược lại dùng format OpenAI chuẩn.
+ (NSData *)bodyForPrompt:(NSString *)prompt tools:(NSArray *)tools cfg:(SBConfig *)cfg {
    NSString *system = cfg.systemPrompt ?: @"";
    NSArray *history = [SBHistory shared].messages;

    if (cfg.bodyTemplate.length) {
        NSString *historyJSON = SBJSONString(history) ?: @"[]";
        NSString *s = cfg.bodyTemplate;
        s = [s stringByReplacingOccurrencesOfString:@"{{SYSTEM}}"  withString:SBJSONEscape(system)];
        s = [s stringByReplacingOccurrencesOfString:@"{{PROMPT}}"  withString:SBJSONEscape(prompt)];
        s = [s stringByReplacingOccurrencesOfString:@"{{HISTORY}}" withString:historyJSON];
        s = [s stringByReplacingOccurrencesOfString:@"{{MODEL}}"   withString:SBJSONEscape(cfg.model ?: @"")];
        return [s dataUsingEncoding:NSUTF8StringEncoding];
    }

    NSMutableArray *messages = [NSMutableArray array];
    if (system.length) [messages addObject:@{@"role": @"system", @"content": system}];
    [messages addObjectsFromArray:history];
    [messages addObject:@{@"role": @"user", @"content": prompt ?: @""}];

    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    body[@"model"]       = cfg.model ?: @"gpt-4o-mini";
    body[@"messages"]    = messages;
    body[@"temperature"] = @(cfg.temperature);
    if (cfg.maxTokens > 0) body[@"max_tokens"] = @(cfg.maxTokens);
    if (tools.count && cfg.useTools) body[@"tools"] = tools;
    return [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
}

+ (void)ask:(NSString *)prompt
      tools:(NSArray *)tools
 completion:(void (^)(NSString *, NSArray *, NSError *))completion {

    SBConfig *cfg = [SBConfig shared];
    void (^done)(NSString *, NSArray *, NSError *) = ^(NSString *a, NSArray *t, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(a, t, e); });
    };

    NSData *body = [self bodyForPrompt:prompt tools:tools cfg:cfg];
    NSMutableURLRequest *req = [self requestForEndpoint:cfg.endpoint
                                                 apiKey:cfg.apiKey
                                           extraHeaders:cfg.extraHeaders
                                                   body:body
                                                timeout:cfg.timeout];
    if (!req) {
        done(nil, nil, [NSError errorWithDomain:@"SiriBridge" code:-1
                                       userInfo:@{NSLocalizedDescriptionKey: @"Endpoint không hợp lệ"}]);
        return;
    }
    SBLog(@"POST %@ model=%@", cfg.endpoint, cfg.model);

    NSURLSessionConfiguration *sc = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    sc.timeoutIntervalForRequest = MAX(5, cfg.timeout);
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sc];
    [[session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        [session finishTasksAndInvalidate];
        if (err) { done(nil, nil, err); return; }
        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        if (code < 200 || code >= 300 || ![json isKindOfClass:[NSDictionary class]]) {
            NSString *snippet = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] substringToIndex:MIN(300u, data.length)];
            NSString *msg = [NSString stringWithFormat:@"HTTP %ld %@", (long)code, snippet ?: @""];
            if ([json isKindOfClass:[NSDictionary class]] && json[@"error"]) {
                id e = json[@"error"];
                msg = [e isKindOfClass:[NSDictionary class]] ? (e[@"message"] ?: msg) : [e description];
            }
            SBLog(@"LLM error: %@", msg);
            done(nil, nil, [NSError errorWithDomain:@"SiriBridge" code:code
                                          userInfo:@{NSLocalizedDescriptionKey: msg}]);
            return;
        }

        // ---- Bóc nội dung trả lời ----
        id content = SBValueAtPath(json, cfg.responseField.length ? cfg.responseField : @"choices.0.message.content");
        // Fallbacks phổ biến: OpenAI mới (content array), Gemini, Anthropic
        if (!content) content = SBValueAtPath(json, @"choices.0.message.content.0.text");
        if (!content) content = SBValueAtPath(json, @"candidates.0.content.parts.0.text");
        if (!content) content = SBValueAtPath(json, @"content.0.text");
        if (!content) content = SBValueAtPath(json, @"response");
        if (!content) content = SBValueAtPath(json, @"output_text");
        if (!content) content = SBValueAtPath(json, @"output.0.content.0.text");
        NSString *answer = [content isKindOfClass:[NSString class]] ? content : nil;

        // ---- tool calls ----
        NSMutableArray *toolCalls = [NSMutableArray array];
        id tc = SBValueAtPath(json, @"choices.0.message.tool_calls");
        if ([tc isKindOfClass:[NSArray class]]) {
            for (id call in tc) {
                id fn = SBValueAtPath(call, @"function");
                NSString *name = SBValueAtPath(fn, @"name");
                NSString *args = SBValueAtPath(fn, @"arguments");
                NSString *cid  = SBValueAtPath(call, @"id");
                if (name) [toolCalls addObject:@{@"id": cid ?: @"", @"name": name, @"arguments": args ?: @"{}"}];
            }
        }
        // Anthropic style
        id contentArr = SBValueAtPath(json, @"content");
        if ([contentArr isKindOfClass:[NSArray class]]) {
            for (id block in contentArr) {
                if (![SBValueAtPath(block, @"type") isEqual:@"tool_use"]) continue;
                [toolCalls addObject:@{@"id": SBValueAtPath(block, @"id") ?: @"",
                                       @"name": SBValueAtPath(block, @"name") ?: @"",
                                       @"arguments": SBJSONString(SBValueAtPath(block, @"input")) ?: @"{}"}];
            }
        }

        if (!answer.length && !toolCalls.count) {
            NSString *dump = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            SBLog(@"Không bóc được nội dung, response: %.400s", dump.UTF8String);
            done(nil, nil, [NSError errorWithDomain:@"SiriBridge" code:-2
                                          userInfo:@{NSLocalizedDescriptionKey:
                                          @"Không đọc được câu trả lời (kiểm tra Response Field)"}]);
            return;
        }
        done(answer, toolCalls.count ? toolCalls : nil, nil);
    }] resume];
}

+ (void)ask:(NSString *)prompt completion:(void (^)(NSString *, NSError *))completion {
    [self ask:prompt tools:nil completion:^(NSString *a, NSArray *t, NSError *e) {
        if (completion) completion(a, e);
    }];
}

@end
