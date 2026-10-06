/*
 * Copyright 2026 Outfox, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/// Creates a manager from resolved providers without acquiring tokens or reading storage.
/// Supply the native manager's store, expiry skew and clock here. The application owns the
/// returned actor and calls `await close()` when its clients are no longer used.
/// Called once for secured settings and never when there are no selected providers.
public typealias TokenManagerFactory = @Sendable ([String: any TokenProvider]) throws -> TokenManager
