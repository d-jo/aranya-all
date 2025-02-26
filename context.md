# Aranya: Access Governance & Secure Data Exchange Platform

## Overview

Aranya is a decentralized access governance and secure data exchange platform that enables organizations to control their critical data and services. It provides a policy-driven approach to access control and secure data exchange without requiring centralized infrastructure.

### Key Features

- **Access Governance**: Define, enforce, and maintain rules and procedures for system security
- **Secure Data Exchange**: Enable encrypted peer-to-peer data transfer between endpoints
- **Decentralized Architecture**: Operate without centralized infrastructure
- **Policy-Driven Control**: Customize access controls through a powerful policy language
- **Audit Trail**: Maintain cryptographically verifiable logs of all commands

## System Architecture

Aranya uses two main planes for operation:

1. **Control Plane**: Handles administrative functionality and access control operations defined in policy
2. **Data Plane**: Manages secure data exchange between endpoints

### Core Components

- **Policy Engine**: Executes policy rules and validates commands
- **DAG (Directed Acyclic Graph)**: Stores immutable command history
- **Fact Database**: Maintains key-value pairs representing system state
- **Crypto Module**: Handles cryptographic operations
- **Aranya Fast Channels (AFC)**: Enables high-throughput data exchange

## Policy Language

Aranya uses a custom policy language to define access controls and system behavior. Here's a basic example:

```policy
---
policy-version: 2
---

// Define a fact schema
fact UserRole[userId id]=>{role string}

// Define a command
command AddUser {
    fields {
        userId id,
        role string,
    }
    
    policy {
        // Check authorization
        check envelope::author_id(envelope) == device::current_user_id()
        
        finish {
            // Create user role fact
            create UserRole[userId: this.userId]=>{role: this.role}
            
            // Emit effect
            emit UserAdded {
                userId: this.userId,
                role: this.role
            }
        }
    }
}

// Define an action
action add_user(userId id, role string) {
    publish AddUser {
        userId: userId,
        role: role
    }
}
```

### Key Policy Concepts

1. **Facts**
   - Key-value pairs stored in the Fact Database (FactDB)
   - Can only be created or mutated by commands
   - Execution order matters - different command orders may result in different fact states
   - Used by policy evaluation to determine command validity
   - Support composite keys and multiple fields
   - Can be marked as immutable for audit trails
   ```policy
   // Basic fact with single key and value
   fact Counter[userId id]=>{count int}
   
   // Complex fact with multiple key and value fields
   fact TeamMember[teamId id, userId id]=>{
       role string,
       joinedAt int,
       permissions string[]
   }
   
   // Immutable fact for audit trails
   immutable fact AuditLog[timestamp int, userId id]=>{
       action string,
       details string
   }
   ```

2. **Commands**
   - Core message type in Aranya protocol
   - Define structured data and policy decisions
   - Must include `seal` and `open` blocks for serialization
   - Can be accepted, rejected, or recalled
   - Stored in DAG for decentralization
   - Execution is atomic - all or nothing
   ```policy
   command Example {
       // Define data structure
       fields {
           data string,
           metadata struct Metadata
       }
       
       // Serialization handlers
       seal {
           return envelope::new(serialize(this))
       }
       
       open {
           return deserialize(envelope::payload(envelope))
       }
       
       // Policy rules
       policy {
           check envelope::author_id(envelope) == device::current_user_id()
           
           finish {
               create ExampleFact[id: this.id]=>{
                   data: this.data,
                   timestamp: ffi::current_time()
               }
           }
       }
       
       // Handle failures
       recall {
           finish {
               emit ExampleFailed {
                   id: this.id,
                   reason: "Command recalled"
               }
           }
       }
   }
   ```

3. **Actions**
   - Entry points for applications to interact with policy
   - Generate and publish commands
   - Atomic execution - all commands must succeed
   - Can perform data transformations
   - Can publish multiple commands
   - Cannot be recursive
   ```policy
   action create_team_with_admin(teamName string, adminId id) {
       // Create team first
       publish CreateTeam {
           name: teamName,
           createdAt: ffi::current_time()
       }
       
       // Then add admin
       publish AddTeamMember {
           teamId: teamName,
           userId: adminId,
           role: "admin"
       }
   }
   ```

4. **Effects**
   - Structured data emitted by policy
   - Used to communicate changes to applications
   - Can be emitted in both finish and recall blocks
   - Include command ID and recall status
   - Cannot contain opaque values
   ```policy
   // Define effect structure
   effect TeamCreated {
       teamId id,
       name string,
       createdAt int
   }
   
   effect TeamMemberAdded {
       teamId id,
       userId id,
       role string
   }
   
   effect OperationFailed {
       operation string,
       reason string,
       timestamp int
   }
   ```

5. **Policy Evaluation Flow**
   - Policy evaluates commands against current fact state
   - Flow: facts₀ → policy(command₀, facts₀) → facts₁ → policy(command₁, facts₁) → ...
   - Commands must be valid and pass verification
   - Evaluation can result in:
     - Acceptance: Command executed and stored in DAG
     - Rejection: Command discarded without fact changes
     - Recall: Command failed after partial execution, requires cleanup
   ```policy
   // Example policy evaluation pattern
   command UpdateResource {
       fields {
           resourceId id,
           newValue string
       }
       
       policy {
           // 1. Verify permissions
           let resource = check_unwrap query Resource[id: this.resourceId]
           check is_owner(envelope::author_id(envelope), this.resourceId)
           
           // 2. Store old state for potential recall
           create ResourceHistory[
               resourceId: this.resourceId,
               timestamp: ffi::current_time()
           ]=>{
               oldValue: resource.value
           }
           
           // 3. Update state
           finish {
               update Resource[id: this.resourceId] to {
                   value: this.newValue
               }
               
               emit ResourceUpdated {
                   resourceId: this.resourceId,
                   newValue: this.newValue
               }
           }
       }
       
       recall {
           // 4. Restore state on failure
           let history = query ResourceHistory[resourceId: this.resourceId]
           if history is Some {
               let old = unwrap history
               finish {
                   update Resource[id: this.resourceId] to {
                       value: old.oldValue
                   }
                   
                   delete ResourceHistory[resourceId: this.resourceId]
                   
                   emit ResourceUpdateFailed {
                       resourceId: this.resourceId,
                       reason: "Update recalled"
                   }
               }
           }
       }
   }
   ```

## Deployment

### System Requirements

- Lightweight platform: <1.5 MB Binary and <1.5 MB RAM
- Built in Rust for safety and performance

### Supported Platforms

- linux/arm
- linux/arm64
- linux/amd64
- macos/arm64 (development)

## Data Exchange Methods

1. **On-Graph (Control Plane)**
   - Low throughput (100s messages/sec)
   - High resilience
   - Broadcast capability

2. **Off-Graph (Data Plane)**
   - High throughput
   - Low latency
   - Point-to-point
   - Automatic encryption

## Security Features

- **Role-Based Access Control (RBAC)**
- **Attribute-Based Access Control (ABAC)**
- **Key Management**
- **Data Segmentation**
- **Revocation Support**
- **Zero-Trust Architecture**

## Use Cases

- Secure IoT device communication
- Enterprise access control
- Secure file sharing
- Embedded systems security
- Identity and Access Management (IAM)

## Implementation Guide

### Policy Development Best Practices

1. **Command Structure**
   - Always include `seal` and `open` blocks for commands to handle serialization
   - Use `check` statements early in policy blocks to fail fast
   - Keep finish blocks atomic - avoid multiple fact operations on the same key
   ```policy
   command Example {
       fields {
           data string
       }
       
       seal {
           return envelope::new(serialize(this))
       }
       
       open {
           return deserialize(envelope::payload(envelope))
       }
       
       policy {
           check envelope::author_id(envelope) == device::current_user_id()
           finish {
               create ExampleFact[id: this.id]=>{data: this.data}
           }
       }
   }
   ```

2. **Fact Management**
   - Design fact schemas to optimize query performance
   - Use immutable facts for audit trails
   - Consider fact lifecycle in policy design
   ```policy
   // Immutable fact example
   immutable fact AuditLog[timestamp int, userId id]=>{action string}
   
   // Queryable fact with multiple key fields
   fact UserPermission[userId id, resource string]=>{
       accessLevel string,
       expiry optional int
   }
   ```

3. **Error Handling**
   - Implement recall blocks for handling command failures and cleaning up facts
   - Use check_unwrap for expected failures
   - Add descriptive effects for error reporting
   - Always clean up related facts in recall blocks
   ```policy
   command CreateTeamMember {
       fields {
           teamId id,
           userId id,
           role string
       }
       
       policy {
           // Verify team exists
           let team = check_unwrap query Team[id: this.teamId]
           
           // Verify user exists
           let user = check_unwrap query User[id: this.userId]
           
           finish {
               // Create team membership
               create TeamMember[teamId: this.teamId, userId: this.userId]=>{
                   role: this.role,
                   joinedAt: ffi::current_time()
               }
               
               // Create role assignment
               create TeamRole[teamId: this.teamId, userId: this.userId]=>{
                   role: this.role
               }
               
               // Add to team count
               let current = unwrap query TeamMemberCount[teamId: this.teamId]
               update TeamMemberCount[teamId: this.teamId] to {
                   count: current.count + 1
               }
               
               emit TeamMemberAdded {
                   teamId: this.teamId,
                   userId: this.userId,
                   role: this.role
               }
           }
       }
       
       recall {
           // Clean up any facts that might have been created before failure
           let member = query TeamMember[teamId: this.teamId, userId: this.userId]
           if member is Some {
               finish {
                   delete TeamMember[teamId: this.teamId, userId: this.userId]
                   delete TeamRole[teamId: this.teamId, userId: this.userId]
                   
                   // Restore team count if it was updated
                   let count = unwrap query TeamMemberCount[teamId: this.teamId]
                   update TeamMemberCount[teamId: this.teamId] to {
                       count: count.count - 1
                   }
                   
                   emit TeamMemberAddFailed {
                       teamId: this.teamId,
                       userId: this.userId,
                       reason: "Operation recalled - cleaning up partial state"
                   }
               }
           }
       }
   }
   
   command UpdatePermission {
       fields {
           userId id,
           resource string,
           newLevel string,
           expiry optional int
       }
       
       policy {
           let current = check_unwrap query UserPermission[
               userId: this.userId,
               resource: this.resource
           ]
           
           // Store old state for potential recall
           create PermissionHistory[
               userId: this.userId,
               resource: this.resource,
               timestamp: ffi::current_time()
           ]=>{
               oldLevel: current.accessLevel,
               oldExpiry: current.expiry
           }
           
           finish {
               update UserPermission[
                   userId: this.userId,
                   resource: this.resource
               ] to {
                   accessLevel: this.newLevel,
                   expiry: this.expiry
               }
           }
       }
       
       recall {
           // Restore previous state from history
           let history = query PermissionHistory[
               userId: this.userId,
               resource: this.resource
           ]
           
           if history is Some {
               let old = unwrap history
               finish {
                   // Restore original permission state
                   update UserPermission[
                       userId: this.userId,
                       resource: this.resource
                   ] to {
                       accessLevel: old.oldLevel,
                       expiry: old.oldExpiry
                   }
                   
                   // Clean up history
                   delete PermissionHistory[
                       userId: this.userId,
                       resource: this.resource
                   ]
                   
                   emit PermissionUpdateFailed {
                       userId: this.userId,
                       reason: "Operation recalled - restored previous state"
                   }
               }
           }
       }
   }
   ```

### Working with Fast Channels (AFC)

1. **Channel Setup**
   ```policy
   // Define channel creation command
   command CreateChannel {
       fields {
           peerId id,
           topic string,
           isDirectional bool
       }
       
       policy {
           // Verify peer has matching topic label
           let peer = check_unwrap query PeerLabel[userId: this.peerId, topic: this.topic]
           
           finish {
               emit CreateAFCChannel {
                   peerId: this.peerId,
                   topic: this.topic,
                   isDirectional: this.isDirectional
               }
           }
       }
   }
   ```

2. **Data Segmentation**
   - Use topic labels to control channel access
   - Implement role checks for channel creation
   - Consider channel lifecycle management

### State Management

1. **Fact Database Patterns**
   - Use composite keys for complex relationships
   - Implement versioning for mutable facts
   - Consider fact cleanup strategies
   ```policy
   // Versioned fact example
   fact UserProfile[userId id, version int]=>{
       name string,
       email string,
       updatedAt int
   }
   ```

2. **Command Synchronization**
   - Design for eventual consistency
   - Handle concurrent updates gracefully
   - Consider command ordering in policy design

### Security Considerations

1. **Access Control**
   - Implement principle of least privilege
   - Use role hierarchies for complex permissions
   - Regular permission auditing
   ```policy
   fact RoleHierarchy[parentRole string]=>{childRole string}
   
   function has_permission(user id, required_role string) bool {
       let user_role = unwrap query UserRole[userId: user]
       if user_role.role == required_role {
           return true
       }
       return exists RoleHierarchy[parentRole: user_role.role, childRole: required_role]
   }
   ```

2. **Key Management**
   - Rotate encryption keys regularly
   - Implement key revocation
   - Secure key storage practices

3. **Audit Logging**
   - Log security-critical operations
   - Include sufficient context in logs
   - Implement log retention policies
   ```policy
   action audit_log(user id, action string) {
       publish CreateAuditLog {
           timestamp: ffi::current_time(),
           userId: user,
           action: action
       }
   }
   ```

## Performance Optimization

1. **Query Optimization**
   - Use appropriate fact indices
   - Minimize fact lookups in hot paths
   - Consider fact denormalization for performance

2. **Command Processing**
   - Batch related operations
   - Use appropriate data plane for throughput requirements
   - Monitor command processing metrics

## Common Patterns

1. **Role-Based Access Control**
   ```policy
   fact Role[name string]=>{
       permissions string[],
       level int
   }
   
   fact UserRole[userId id]=>{
       roleName string,
       grantedBy id,
       grantedAt int
   }
   ```

2. **Resource Ownership**
   ```policy
   fact ResourceOwner[resourceId id]=>{
       ownerId id,
       createdAt int
   }
   
   function is_owner(user id, resource id) bool {
       let ownership = unwrap query ResourceOwner[resourceId: resource]
       return ownership.ownerId == user
   }
   ```


## Documentation

For detailed documentation, please refer to the following resources:

- [Aranya Overview](docs/aranya-overview.md)
- [Policy Language v1](docs/policy-v1.md)
- [Policy Language v2](docs/policy-v2.md)
- [Aranya Fast Channels](docs/afc.md)
- [Architecture Guide](docs/aranya-architecture.md) 