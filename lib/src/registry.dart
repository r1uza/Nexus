import 'config.dart';
import 'errors.dart';
import 'model.dart';

final class EndpointPolicy {
  EndpointPolicy(Set<String> allowedHosts)
      : _allowedHosts =
            allowedHosts.map((String host) => host.toLowerCase()).toSet();

  final Set<String> _allowedHosts;

  void validate(Uri endpoint) {
    if (!endpoint.hasScheme ||
        !endpoint.hasAuthority ||
        endpoint.userInfo.isNotEmpty ||
        (endpoint.scheme != 'http' && endpoint.scheme != 'https')) {
      throw const NexusException(
        'endpoint_invalid',
        'Endpoint must be an absolute http(s) URI without userinfo',
      );
    }
    final host = endpoint.host.toLowerCase();
    if (!isLoopbackHost(host) && !_allowedHosts.contains(host)) {
      throw NexusException(
        'endpoint_denied',
        'Endpoint host is not allowlisted: $host',
        statusCode: 403,
      );
    }
  }
}

final class NodeRegistry {
  NodeRegistry({required this.endpointPolicy});

  final EndpointPolicy endpointPolicy;
  final Map<String, NodeDefinition> _nodes = <String, NodeDefinition>{};

  List<NodeDefinition> get nodes {
    final result = _nodes.values.toList()
      ..sort(
        (NodeDefinition left, NodeDefinition right) =>
            left.id.compareTo(right.id),
      );
    return List<NodeDefinition>.unmodifiable(result);
  }

  void register(NodeDefinition node) {
    if (_nodes.containsKey(node.id)) {
      throw NexusException('node_exists', 'Node already exists: ${node.id}');
    }
    if (node.transport == TransportKind.http) {
      endpointPolicy.validate(node.endpoint!);
    }
    _nodes[node.id] = node;
  }

  bool remove(String nodeId) {
    final node = _nodes[nodeId];
    if (node == null) return false;
    if (!node.mutable) {
      throw NexusException(
        'node_immutable',
        'Built-in node cannot be removed: $nodeId',
        statusCode: 403,
      );
    }
    _nodes.remove(nodeId);
    return true;
  }

  NodeDefinition resolve(String capability, {String? targetNode}) {
    if (targetNode != null) {
      final node = _nodes[targetNode];
      if (node == null ||
          !node.enabled ||
          !node.capabilities.contains(capability)) {
        throw const NexusException(
          'route_not_found',
          'No enabled target exposes the requested capability',
          statusCode: 404,
        );
      }
      return node;
    }
    final matches = _nodes.values
        .where(
          (NodeDefinition node) =>
              node.enabled && node.capabilities.contains(capability),
        )
        .toList();
    if (matches.isEmpty) {
      throw const NexusException(
        'route_not_found',
        'No enabled node exposes the requested capability',
        statusCode: 404,
      );
    }
    if (matches.length > 1) {
      throw const NexusException(
        'route_ambiguous',
        'More than one node exposes the capability; targetNode is required',
        statusCode: 409,
      );
    }
    return matches.single;
  }
}
