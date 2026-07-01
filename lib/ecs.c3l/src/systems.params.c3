module ecs;

import world;

typedef Res (SystemParam) <Type> = inline Type;

macro typeid Res.type_a(Res* self) { return Type::typeid; }

typedef ResMut (SystemParam) <Type> = inline Type;

macro typeid ResMut.type_a(ResMut* self) { return Type::typeid; }

struct Query (SystemParam) <TypeA, TypeB, TypeC, TypeD, TypeE, TypeF, TypeG, TypeH>
{
	QueryIter{TypeA, TypeB, TypeC, TypeD, TypeE, TypeF, TypeG, TypeH} iter;
}

macro typeid Query.type_a(Query* self) { return TypeA::typeid; }
macro typeid Query.type_b(Query* self) { return TypeB::typeid; }
macro typeid Query.type_c(Query* self) { return TypeC::typeid; }
macro typeid Query.type_d(Query* self) { return TypeD::typeid; }
macro typeid Query.type_e(Query* self) { return TypeE::typeid; }
macro typeid Query.type_f(Query* self) { return TypeF::typeid; }
macro typeid Query.type_g(Query* self) { return TypeG::typeid; }
macro typeid Query.type_h(Query* self) { return TypeH::typeid; }

macro void Query.init_system_param(Query* this, World* world)
{
	this.iter = world.query(TypeA, TypeB, TypeC, TypeD, TypeE, TypeF, TypeG, TypeH);
}

macro Query.next(Query* self)
{
	return self.iter.next();
}

typedef On(SystemParam)<EventType> = bool;


macro typeid On.type_a(On* self) { return EventType::typeid; }

macro void On.init_system_param(On* this, World* world)
{
	// Nothing to initialize
}

struct MessageWriter (SystemParam) <MessageType>
{
	World* world;
}

macro typeid MessageWriter.type_a(MessageWriter* self) { return MessageType::typeid; }

macro void MessageWriter.init_system_param(MessageWriter* this, World* world)
{
	this.world = world;
}

macro void MessageWriter.send(MessageWriter* self, MessageType msg)
{
	self.world.send_message(MessageType::typeid, (void*)&msg, (uint)MessageType::size);
}

struct MessageReader (SystemParam) <MessageType>
{
	World* world;
	uint index;
}

macro typeid MessageReader.type_a(MessageReader* self) { return MessageType::typeid; }

macro void MessageReader.init_system_param(MessageReader* this, World* world)
{
	this.world = world;
	this.index = 0;
}

macro MessageType* MessageReader.read(MessageReader* self)
{
	while (self.index < self.world.message_queue.records_len)
	{
		if (self.world.message_queue.records[self.index].type == MessageType::typeid)
		{
			MessageType* msg = (MessageType*)self.world.message_queue.records[self.index].data;
			self.index++;
			return msg;
		}
		self.index++;
	}
	return (MessageType*)null;
}

struct Commands (SystemParam)
{
	World* world;
}

macro void Commands.init_system_param(Commands* this, World* world)
{
	this.world = world;
}

fn ecs::Entity Commands.spawn(Commands* this)
{
	return this.world.deferred_spawn();
}

macro void Commands.@add(Commands* self, ecs::Entity entity, #value)
{
	$Typefrom($Typeof(#value))* heap_copy = alloc::malloc(self.world.allocator, $Typeof(#value)::size);
	*heap_copy = #value;
	self.world.enqueue_command({
		.kind = world::CommandKind.ADD_COMPONENT,
		.entity = entity,
		.type = $Typeof(#value)::typeid,
		.data = (void*)heap_copy,
		.size = (uint)$Typeof(#value)::size,
		.deinitializer = null
	});
}

macro void Commands.@remove(Commands* self, ecs::Entity entity, $ComponentType)
{
	self.world.enqueue_command({
		.kind = world::CommandKind.REMOVE_COMPONENT,
		.entity = entity,
		.type = $ComponentType::typeid,
		.data = null,
		.size = 0,
		.deinitializer = null
	});
}

macro void Commands.@despawn(Commands* self, ecs::Entity entity)
{
	self.world.enqueue_command({
		.kind = world::CommandKind.DESPAWN,
		.entity = entity,
		.type = void::typeid,
		.data = null,
		.size = 0,
		.deinitializer = null
	});
}

macro void Commands.@add_resource(Commands* self, #value)
{
	$if $Typeof(#value)::kind == TypeKind.POINTER:
		{
			$Typefrom($Typeof(*#value))* heap_copy = alloc::malloc(self.world.allocator, $Typeof(*#value)::size);
			*heap_copy = *#value;
			self.world.enqueue_command({
				.kind = world::CommandKind.ADD_RESOURCE,
				.entity = {},
				.type = $Typeof(*#value)::typeid,
				.data = (void*)heap_copy,
				.size = 0,
				.deinitializer = &deinit_wrapper{$Typeof(*#value)}
			});
		}
	$else
		{
			$Typefrom($Typeof(#value))* heap_copy = alloc::malloc(self.world.allocator, $Typeof(#value)::size);
			*heap_copy = #value;
			self.world.enqueue_command({
				.kind = world::CommandKind.ADD_RESOURCE,
				.entity = {},
				.type = $Typeof(#value)::typeid,
				.data = (void*)heap_copy,
				.size = 0,
				.deinitializer = &deinit_wrapper{$Typeof(#value)}
			});
		}
	$endif
}
