import Glib
import Foundation

public class Socket: SocketReader, SocketWriter {

	// MARK: Enums
	
	// MARK: -- AddressFamily
	
	///
	/// Socket Address Family Values
	///
	/// **Note:** Only the following are supported at this time:
	///			inet = AF_INET (IPV4)
	///			inet6 = AF_INET6 (IPV6)
	///
	public enum AddressFamily {
		
		/// AF_INET (IPV4)
		case inet
		
		/// AF_INET6 (IPV6)
		case inet6
		
		///
		/// Return enum equivalent of a raw value
		///
		/// - Parameter forValue: Value for which enum value is desired
		///
		/// - Returns: Optional contain enum value or nil
		///
		static func getFamily(forValue: Int32) -> AddressFamily? {
			
			switch forValue {
				
			case Int32(AF_INET):
				return .inet
			case Int32(AF_INET6):
				return .inet6
			default:
				return nil
			}
		}
		
	}


	// MARK: -- SocketType
	
	///
	/// Socket Type Values
	///
	/// **Note:** Only the following are supported at this time:
	///			stream = SOCK_STREAM (Provides sequenced, reliable, two-way, connection-based byte streams.)
	///			datagram = SOCK_DGRAM (Supports datagrams (connectionless, unreliable messages of a fixed maximum length).)
	///
	public enum SocketType {
		
		/// SOCK_STREAM (Provides sequenced, reliable, two-way, connection-based byte streams.)
		case stream
		
		/// SOCK_DGRAM (Supports datagrams (connectionless, unreliable messages of a fixed maximum length).)
		case datagram
		
		///
		/// Return enum equivalent of a raw value
		///
		/// - Parameter forValue: Value for which enum value is desired
		///
		/// - Returns: Optional contain enum value or nil
		///
		static func getType(forValue: Int32) -> SocketType? {
			
			switch forValue {
				
			case Int32(SOCK_STREAM.rawValue):
				return .stream
			case Int32(SOCK_DGRAM.rawValue):
				return .datagram
			default:
				return nil
			}
		}
	}

	// MARK: -- SocketProtocol
	
	///
	/// Socket Protocol Values
	///
	/// **Note:** Only the following are supported at this time:
	///			tcp = IPPROTO_TCP
	///			udp = IPPROTO_UDP
	///
	public enum SocketProtocol: Int32 {
		
		/// IPPROTO_TCP
		case tcp
		
		/// IPPROTO_UDP
		case udp
		
		///
		/// Return the value for a particular case
		///
		var value: Int32 {
			
			switch self {
				
			case .tcp:
				return Int32(IPPROTO_TCP)
			case .udp:
				return Int32(IPPROTO_UDP)
			}
		}
		
		///
		/// Return enum equivalent of a raw value
		///
		/// - Parameter forValue: Value for which enum value is desired
		///
		/// - Returns: Optional contain enum value or nil
		///
		static func getProtocol(forValue: Int32) -> SocketProtocol? {
			
			switch forValue {
				
			case Int32(IPPROTO_TCP):
				return .tcp
			case Int32(IPPROTO_UDP):
				return .udp
			default:
				return nil
			}
		}
	}

	// MARK: Class Methods
	
	///
	/// Create a configured Socket instance.
	/// **Note:** Calling with no passed parameters will create a default socket: IPV4, stream, TCP.
	///
	/// - Parameters:
	///		- family:	The family of the socket to create.
	///		- type:		The type of socket to create.
	///		- proto:	The protocool to use for the socket.
	///
	/// - Returns: New Socket instance
	///
	public class func create(family: ProtocolFamily = .inet, type: SocketType = .stream, proto: SocketProtocol = .tcp) throws -> Socket {
		
		if type == .datagram || proto == .udp {
			
			throw Error(code: Socket.SOCKET_ERR_NOT_SUPPORTED_YET, reason: "Full support for Datagrams and UDP not available yet.")
			
		}
		return try Socket(family: family, type: type, proto: proto)
	}

	// MARK: Lifecycle Methods
	
	// MARK: -- Public
	
	///
	/// Internal initializer to create a configured Socket instance.
	///
	/// - Parameters:
	///		- family:	The family of the socket to create.
	///		- type:		The type of socket to create.
	///		- proto:	The protocool to use for the socket.
	///
	/// - Returns: New Socket instance
	///
	public init(family: AddressFamily = .inet, type: SocketType = .stream, protocol: SocketProtocol = .tcp) {
		
		if type == .datagram || protocol == .udp {
			
			print("Full support for Datagrams and UDP not available yet.")
			
		}

		// Initialize the read buffer...
		self.readBuffer.initialize(to: 0)
		
		// Create the socket...
		self.socketfd = Glibc.socket(family.value, type.value, protocol.value)
		
		// If error, throw an appropriate exception...
		if self.socketfd < 0 {
			
			print("Unable to Create Socket")
			return
		}

		return self
		
	}

	///
	/// Cleanup: close the socket, free memory buffers.
	///
	deinit {
		
		if self.socketfd > 0 {
			
			self.close()
		}
		
		// Destroy and free the readBuffer...
		self.readBuffer.deinitialize()
		self.readBuffer.deallocate(capacity: self.readBufferSize)
		
		// If we have a delegate, tell it to cleanup too...
		self.delegate?.deinitialize()
	}

	// MARK: -- Listen
	
	///
	/// Listen on a port, limiting the maximum number of pending connections.
	///
	/// - Parameters:
	///		- port: 				The port to listen on.
	/// 	- maxBacklogSize: 		The maximum size of the queue containing pending connections. Default is *Socket.SOCKET_DEFAULT_MAX_BACKLOG*.
	///
	public func listen(on port: Int, maxBacklogSize: Int = 50) throws {
		
		// Set a flag so that this address can be re-used immediately after the connection
		// closes.  (TCP normally imposes a delay before an address can be re-used.)
		var on: Int32 = 1
		if setsockopt(self.socketfd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size)) < 0 {

			print("set socketopt failed")
			
		}
		
		#if !os(Linux)
			// Set the socket to ignore SIGPIPE to avoid dying on interrupted connections...
			//	Note: Linux does not support the SO_NOSIGPIPE option. Instead, we use the
			//		  MSG_NOSIGNAL flags passed to send.  See the writeData() functions below.
			if setsockopt(self.socketfd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size)) < 0 {
				
				throw Error(code: Socket.SOCKET_ERR_SETSOCKOPT_FAILED, reason: self.lastError())
			}
		#endif
		
		// Get the signature for the socket...
		guard let sig = self.signature else {
			
			throw Error(code: Socket.SOCKET_ERR_INTERNAL, reason: "Socket signature not found.")
		}
		
		// Tell the delegate to initialize as a server...
		do {
			
			try self.delegate?.initialize(asServer: true)
			
		} catch let error {
			
			guard let sslError = error as? SSLError else {
				
				throw error
			}
			
			throw Error(with: sslError)
		}
		
		// Create the hints for our search...
		#if os(Linux)
			var hints = addrinfo(
				ai_flags: AI_PASSIVE,
				ai_family: sig.protocolFamily.value,
				ai_socktype: sig.socketType.value,
				ai_protocol: 0,
				ai_addrlen: 0,
				ai_addr: nil,
				ai_canonname: nil,
				ai_next: nil)
		#else
			var hints = addrinfo(
				ai_flags: AI_PASSIVE,
				ai_family: sig.protocolFamily.value,
				ai_socktype: sig.socketType.value,
				ai_protocol: 0,
				ai_addrlen: 0,
				ai_canonname: nil,
				ai_addr: nil,
				ai_next: nil)
		#endif
		
		var targetInfo: UnsafeMutablePointer<addrinfo>? = UnsafeMutablePointer<addrinfo>.allocate(capacity: 1)
		
		// Retrieve the info on our target...
		let status: Int32 = getaddrinfo(nil, String(port), &hints, &targetInfo)
		if status != 0 {
			
			var errorString: String
			if status == EAI_SYSTEM {
				errorString = String(validatingUTF8: strerror(errno)) ?? "Unknown error code."
			} else {
				errorString = String(validatingUTF8: gai_strerror(errno)) ?? "Unknown error code."
			}
			throw Error(code: Socket.SOCKET_ERR_GETADDRINFO_FAILED, reason: errorString)
		}
		
		// Defer cleanup of our target info...
		defer {
			
			if targetInfo != nil {
				freeaddrinfo(targetInfo)
			}
		}
		
		var info = targetInfo
		var bound = false
		while info != nil {
			
			// Try to bind the socket to the address...
			#if os(Linux)
				if Glibc.bind(self.socketfd, info!.pointee.ai_addr, info!.pointee.ai_addrlen) == 0 {
					
					// Success... We've found our address...
					bound = true
					break
				}
			#else
				if Darwin.bind(self.socketfd, info!.pointee.ai_addr, info!.pointee.ai_addrlen) == 0 {
					
					// Success... We've found our address...
					bound = true
					break
				}
			#endif
			
			// Try the next one...
			info = info?.pointee.ai_next
		}
		
		// Throw an error if we weren't able to bind to an address...
		if !bound {
			
			throw Error(code: Socket.SOCKET_ERR_BIND_FAILED, reason: self.lastError())
		}
		
		// Save the address info...
		var address: Address
		
		// If the port was set to zero, we need to retrieve the port that assigned by the OS...
		if port == 0 {
		
			let addr = sockaddr_storage()
			var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
			var addrPtr = addr.asAddr()
			if getsockname(self.socketfd, &addrPtr, &length) == 0 {
				
				if addrPtr.sa_family == sa_family_t(AF_INET6) {
					
					var addr = sockaddr_in6()
					memcpy(&addr, &addrPtr, Int(MemoryLayout<sockaddr_in6>.size))
					address = .ipv6(addr)
					
				} else if addrPtr.sa_family == sa_family_t(AF_INET) {
					
					var addr = sockaddr_in()
					memcpy(&addr, &addrPtr, Int(MemoryLayout<sockaddr_in>.size))
					address = .ipv4(addr)
					
				} else {
					
					throw Error(code: Socket.SOCKET_ERR_WRONG_PROTOCOL, reason: "Unable to determine listening socket protocol family.")
				}
				
			} else {
				
				throw Error(code: Socket.SOCKET_ERR_BIND_FAILED, reason: "Unable to determine listening socket address after bind.")
			}
		
		} else {
		
			if info!.pointee.ai_family == Int32(AF_INET6) {
			
				var addr = sockaddr_in6()
				memcpy(&addr, info!.pointee.ai_addr, Int(MemoryLayout<sockaddr_in6>.size))
				address = .ipv6(addr)
		
			} else if info!.pointee.ai_family == Int32(AF_INET) {
		
				var addr = sockaddr_in()
				memcpy(&addr, info!.pointee.ai_addr, Int(MemoryLayout<sockaddr_in>.size))
				address = .ipv4(addr)
		
			} else {
			
				throw Error(code: Socket.SOCKET_ERR_WRONG_PROTOCOL, reason: "Unable to determine listening socket protocol family.")
			}
			
		}
		
		self.signature?.address = address
		
		// Update our hostname and port...
		if let (hostname, port) = Socket.hostnameAndPort(from: address) {
			self.signature?.hostname = hostname
			self.signature?.port = Int32(port)
		}
		
		// Now listen for connections...
		#if os(Linux)
			if Glibc.listen(self.socketfd, Int32(maxBacklogSize)) < 0 {
				
				throw Error(code: Socket.SOCKET_ERR_LISTEN_FAILED, reason: self.lastError())
			}
		#else
			if Darwin.listen(self.socketfd, Int32(maxBacklogSize)) < 0 {
				
				throw Error(code: Socket.SOCKET_ERR_LISTEN_FAILED, reason: self.lastError())
			}
		#endif
		
		self.isListening = true
		self.signature?.isSecure = self.delegate != nil ? true : false
	}




}