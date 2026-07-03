module world;

import ecs;
import archetype;
import std::core::mem;
import std::collections::list;
import std::thread;

struct EntityRecord @export("EntityRecord")
{
	Archetype* archetype;
	uint row;
	uint gen;
	bool active;
}

struct MessageRecord @export("MessageRecord")
{
	typeid type;
	void* data;
	uint size;
}

struct MessageQueue @export("MessageQueue")
{
	List{MessageRecord} records;
}

enum CommandKind @export("CommandKind")
{
	SPAWN,
	DESPAWN,
	ADD_COMPONENT,
	REMOVE_COMPONENT,
	ADD_RESOURCE
}

struct Command @export("Command")
{
	CommandKind kind;
	ecs::Entity entity;
	typeid type;
	void* data;
	uint size;
	ecs::Deinitializer deinitializer;
}

struct World @export("World")
{
	Allocator allocator;
	EntityRecord[] entity_records;
	uint entity_records_len;
	uint entity_records_cap;

	uint[] free_records;
	uint free_records_len;
	uint free_records_cap;

	Archetype*[] archetypes;
	uint archetypes_len;
	uint archetypes_cap;

	Archetype* empty_archetype;

	ResourceRecord[] resources;
	uint resources_len;
	uint resources_cap;

	MessageQueue message_queue;

	Command[] commands;
	uint commands_len;
	uint commands_cap;
	Mutex commands_mutex;
	uint deferred_spawn_count;
}

fn void ensure_entity_records_capacity(World* self, usz new_cap) @private
{
	if (new_cap <= self.entity_records_cap) return;
	if (new_cap < 8)
	{
		new_cap = 8;
	}
	else if (new_cap < (usz)self.entity_records_cap * 2)
	{
		new_cap = (usz)self.entity_records_cap * 2;
	}

	self.entity_records = alloc::realloc_array(self.allocator, self.entity_records.ptr, EntityRecord, (sz)new_cap);
	self.entity_records = self.entity_records.ptr[0..self.entity_records_len];
	self.entity_records_cap = (uint)new_cap;
}

fn void ensure_free_records_capacity(World* self, usz new_cap) @private
{
	if (new_cap <= self.free_records_cap) return;
	if (new_cap < 8)
	{
		new_cap = 8;
	}
	else if (new_cap < (usz)self.free_records_cap * 2)
	{
		new_cap = (usz)self.free_records_cap * 2;
	}

	self.free_records = alloc::realloc_array(self.allocator, self.free_records.ptr, uint, (sz)new_cap);
	self.free_records = self.free_records.ptr[0..self.free_records_len];
	self.free_records_cap = (uint)new_cap;
}

fn void ensure_archetypes_capacity(World* self, usz new_cap) @private
{
	if (new_cap <= self.archetypes_cap) return;
	if (new_cap < 8)
	{
		new_cap = 8;
	}
	else if (new_cap < (usz)self.archetypes_cap * 2)
	{
		new_cap = (usz)self.archetypes_cap * 2;
	}

	self.archetypes = alloc::realloc_array(self.allocator, self.archetypes.ptr, Archetype*, (sz)new_cap);
	self.archetypes = self.archetypes.ptr[0..self.archetypes_len];
	self.archetypes_cap = (uint)new_cap;
}

fn World new(Allocator allocator) @export("world_new")
{
	World self = { };
	self.allocator = allocator;

	// Create empty archetype
	typeid[] empty_types = { };
	self.empty_archetype = alloc::new(allocator, Archetype);
	*self.empty_archetype = archetype::new(empty_types, allocator);

	ensure_archetypes_capacity(&self, 1);
	self.archetypes_len = 1;
	self.archetypes = self.archetypes.ptr[0..1];
	self.archetypes[0] = self.empty_archetype;

	self.commands_mutex.init()!!;
	self.deferred_spawn_count = 0;
	self.message_queue.records.init(allocator, 16);

	return self;
}

fn void World.deinit(World* self) @export("world_deinit")
{
	self.commands_mutex.destroy();

	for (uint i = 0; i < self.commands_len; i++)
	{
		if (self.commands[i].data != null)
		{
			if (self.commands[i].kind == CommandKind.ADD_RESOURCE && self.commands[i].deinitializer != null)
			{
				self.commands[i].deinitializer(self.commands[i].data, self.allocator);
			}
			alloc::free(self.allocator, self.commands[i].data);
		}
	}
	if (self.commands.ptr != null)
	{
		alloc::free(self.allocator, self.commands.ptr);
	}

	for (uint i = 0; i < self.archetypes_len; i++)
	{
		self.archetypes[i].deinit(self.allocator);
		alloc::free(self.allocator, self.archetypes[i]);
	}

	if (self.entity_records.ptr != null)
	{
		alloc::free(self.allocator, self.entity_records.ptr);
	}
	if (self.free_records.ptr != null)
	{
		alloc::free(self.allocator, self.free_records.ptr);
	}
	if (self.archetypes.ptr != null)
	{
		alloc::free(self.allocator, self.archetypes.ptr);
	}

	// Free resources array and their allocations
	self.clear_resources();

	// Free message queue and records
	for (sz i = 0; i < self.message_queue.records.len(); i++)
	{
		alloc::free(self.allocator, self.message_queue.records[i].data);
	}
	self.message_queue.records.free();

	*self = { };
}



fn void World.send_message(World* self, typeid type, void* data, uint size) @export("world_send_message")
{
	void* copy = alloc::malloc(self.allocator, size);
	mem::copy(copy, data, (usz)size);
	self.message_queue.records.push({ type, copy, size });
}

fn void World.clear_messages(World* self) @export("world_clear_messages")
{
	for (sz i = 0; i < self.message_queue.records.len(); i++)
	{
		alloc::free(self.allocator, self.message_queue.records[i].data);
	}
	self.message_queue.records.clear();
}

fn ecs::Entity World.spawn(World* self) @export("world_spawn")
{
	ulong id;
	uint gen;
	uint record_idx;

	if (self.free_records_len > 0)
	{
		record_idx = self.free_records[self.free_records_len - 1];
		self.free_records_len--;
		self.free_records = self.free_records.ptr[0..self.free_records_len];
		id = (ulong)record_idx;
		gen = self.entity_records[record_idx].gen;
	}
	else
	{
		record_idx = self.entity_records_len;
		id = (ulong)record_idx;
		gen = 0;
		ensure_entity_records_capacity(self, (usz)record_idx + 1);
		self.entity_records_len++;
		self.entity_records = self.entity_records.ptr[0..self.entity_records_len];
	}

	ecs::Entity entity = { .id = id, .gen = gen };

	// Add to empty archetype
	uint row = self.empty_archetype.add_entity(self.allocator, entity);

	EntityRecord record = { .archetype = self.empty_archetype, .row = row, .gen = gen, .active = true };

	self.entity_records[record_idx] = record;
	return entity;
}

fn bool World.is_alive(World* self, ecs::Entity entity) @export("world_is_alive")
{
	if (entity.id >= self.entity_records_len) return false;
	EntityRecord* record = &self.entity_records[entity.id];
	return record.active && record.gen == entity.gen;
}

fn void World.despawn(World* self, ecs::Entity entity) @export("world_despawn")
{
	if (!self.is_alive(entity)) return;
	EntityRecord* record = &self.entity_records[entity.id];

	ecs::Entity moved_entity = record.archetype.remove_at(record.row);
	if (moved_entity.id != entity.id)
	{
		self.entity_records[moved_entity.id].row = record.row;
	}

	record.active = false;
	record.gen++;

	ensure_free_records_capacity(self, (usz)self.free_records_len + 1);
	self.free_records_len++;
	self.free_records = self.free_records.ptr[0..self.free_records_len];
	self.free_records[self.free_records_len - 1] = (uint)entity.id;
}

fn void sort_types(typeid[] types) @private
{
	for (uint i = 1; i < types.len; i++)
	{
		typeid key   = types[i];
		uptr key_val = (uptr)key;
		int j        = (int)i - 1;
		while (j >= 0 && (uptr)types[j] > key_val)
		{
			types[j + 1] = types[j];
			j--;
		}
		types[j + 1] = key;
	}
}

fn Archetype* get_or_create_archetype(World* self, typeid[] types) @private
{
	typeid[] sorted_types = alloc::alloc_array(self.allocator, typeid, types.len);
	mem::copy(sorted_types.ptr, types.ptr, types.len * uptr::size);
	sort_types(sorted_types);
	defer alloc::free(self.allocator, sorted_types.ptr);

	for (uint i = 0; i < self.archetypes_len; i++)
	{
		Archetype* arch = self.archetypes[i];
		if (arch.component_types.len != sorted_types.len) continue;

		bool match = true;
		for (uint j = 0; j < sorted_types.len; j++)
		{
			if (arch.component_types[j] != sorted_types[j])
			{
				match = false;
				break;
			}
		}

		if (match)
		{
			return arch;
		}
	}

	Archetype* new_arch = alloc::new(self.allocator, Archetype);
	*new_arch = archetype::new(sorted_types, self.allocator);

	ensure_archetypes_capacity(self, (usz)self.archetypes_len + 1);
	self.archetypes_len++;
	self.archetypes = self.archetypes.ptr[0..self.archetypes_len];
	self.archetypes[self.archetypes_len - 1] = new_arch;

	return new_arch;
}

fn bool World.has_component(World* self, ecs::Entity entity, typeid type) @export("world_has_component")
{
	if (!self.is_alive(entity)) return false;
	EntityRecord* record = &self.entity_records[entity.id];
	return record.archetype.find_column(type) >= 0;
}

fn void* World.get_component(World* self, ecs::Entity entity, typeid type) @export("world_get_component")
{
	if (!self.is_alive(entity)) return null;
	EntityRecord* record = &self.entity_records[entity.id];
	int col              = record.archetype.find_column(type);
	if (col < 0) return null;
	ComponentColumn column = record.archetype.get_column((uint)col);
	return column[record.row];
}

fn void*[] World.get_all_components(World* self, ecs::Entity entity) @export("world_get_all_components")
{
	if (!self.is_alive(entity)) return {};
	EntityRecord* record = &self.entity_records[entity.id];
	Archetype* arch      = record.archetype;

	void*[] components = alloc::alloc_array(self.allocator, void*, arch.component_types.len);
	defer alloc::free(self.allocator, components.ptr);

	for (uint i = 0; i < arch.component_types.len; i++)
	{
		ComponentColumn column = arch.get_column(i);
		components[i] = column[record.row];
	}

	return components;
}

fn void World.add_component(World* self, ecs::Entity entity, typeid type, void* data) @export("world_add_component")
{
	if (!self.is_alive(entity)) return;
	EntityRecord* record = &self.entity_records[entity.id];
	Archetype* old_arch  = record.archetype;
	uint old_row         = record.row;

	int col = old_arch.find_column(type);
	if (col >= 0)
	{
		if (data != null)
		{
			ComponentColumn column = old_arch.get_column((uint)col);
			mem::copy(column[old_row], data, (usz)type.size);
		}
		return;
	}

	uint new_len       = old_arch.component_types.len + 1;
	typeid[] new_types = alloc::alloc_array(self.allocator, typeid, new_len);
	defer alloc::free(self.allocator, new_types.ptr);

	mem::copy(new_types.ptr, old_arch.component_types.ptr, old_arch.component_types.len * uptr::size);
	new_types[new_len - 1] = type;

	Archetype* new_arch = get_or_create_archetype(self, new_types);
	uint new_row        = new_arch.add_entity(self.allocator, entity);

	for (uint i = 0; i < old_arch.component_types.len; i++)
	{
		typeid t        = old_arch.component_types[i];
		int old_col_idx = (int)i;
		int new_col_idx = new_arch.find_column(t);
		assert(new_col_idx >= 0);

		ComponentColumn old_col = old_arch.get_column((uint)old_col_idx);
		ComponentColumn new_col = new_arch.get_column((uint)new_col_idx);

		mem::copy(new_col[new_row], old_col[old_row], (usz)t.size);
	}

	int new_col_idx = new_arch.find_column(type);
	assert(new_col_idx >= 0);
	ComponentColumn new_col = new_arch.get_column((uint)new_col_idx);
	if (data != null)
	{
		mem::copy(new_col[new_row], data, (usz)type.size);
	}
	else
	{
		mem::set(new_col[new_row], 0, (usz)type.size);
	}

	ecs::Entity moved_entity = old_arch.remove_at(old_row);
	if (moved_entity.id != entity.id)
	{
		self.entity_records[moved_entity.id].row = old_row;
	}

	record.archetype = new_arch;
	record.row = new_row;
}

fn void World.remove_component(World* self, ecs::Entity entity, typeid type) @export("world_remove_component")
{
	if (!self.is_alive(entity)) return;
	EntityRecord* record = &self.entity_records[entity.id];
	Archetype* old_arch  = record.archetype;
	uint old_row         = record.row;

	int col = old_arch.find_column(type);
	if (col < 0) return;

	uint new_len       = old_arch.component_types.len - 1;
	typeid[] new_types = alloc::alloc_array(self.allocator, typeid, new_len);
	defer alloc::free(self.allocator, new_types.ptr);

	uint dst_idx = 0;
	for (uint i = 0; i < old_arch.component_types.len; i++)
	{
		if (i == (uint)col) continue;
		new_types[dst_idx] = old_arch.component_types[i];
		dst_idx++;
	}

	Archetype* new_arch = get_or_create_archetype(self, new_types);
	uint new_row        = new_arch.add_entity(self.allocator, entity);

	for (uint i = 0; i < old_arch.component_types.len; i++)
	{
		if (i == (uint)col) continue;
		typeid t        = old_arch.component_types[i];
		int old_col_idx = (int)i;
		int new_col_idx = new_arch.find_column(t);
		assert(new_col_idx >= 0);

		ComponentColumn old_col = old_arch.get_column((uint)old_col_idx);
		ComponentColumn new_col = new_arch.get_column((uint)new_col_idx);

		mem::copy(new_col[new_row], old_col[old_row], (usz)t.size);
	}

	ecs::Entity moved_entity = old_arch.remove_at(old_row);
	if (moved_entity.id != entity.id)
	{
		self.entity_records[moved_entity.id].row = old_row;
	}

	record.archetype = new_arch;
	record.row = new_row;
}

fn uint World.count(World* self) {
	return self.entity_records_len - self.free_records_len;
}


<*
Add a component of type `ComponentType` to the specified entity in the world. If the entity already has a component of this type, it will be updated with the new value.
*>
fn void add(World* self, ecs::Entity entity, ComponentType value)<ComponentType>
{
	self.add_component(entity, ComponentType::typeid, &value);
}

<*
Remove a component of type `ComponentType` from the specified entity in the world. If the entity does not have a component of this type, this function does nothing.
*>
fn void remove(World* self, ecs::Entity entity)<ComponentType>
{
	self.remove_component(entity, ComponentType::typeid);
}

<*
Check if the specified entity has a component of type `ComponentType` in the world.
Returns `true` if the entity has the component, `false` otherwise or if the entity is not alive.
*>
fn bool has(World* self, ecs::Entity entity)<ComponentType>
{
	return self.has_component(entity, ComponentType::typeid);
}

<*
Get a pointer to the component of type `ComponentType` for the specified entity in the world. Returns `null` if the entity does not have the component or if the entity is not alive.
*>
fn ComponentType* get(World* self, ecs::Entity entity)<ComponentType>
{
	return (ComponentType*)self.get_component(entity, ComponentType::typeid);
}

struct QueryIterBase @export("QueryIterBase")
{
	World* world;
	uint archetype_idx;
	uint row_idx;
	uint cached_archetype_idx;
	int[8] component_columns;
	typeid[8] include_types;
	ushort include_len;
	typeid[8] exclude_types;
	ushort exclude_len;
}

struct QueryIter <TypeA, TypeB, TypeC, TypeD, TypeE, TypeF, TypeG, TypeH>
{
	inline QueryIterBase base;
	ecs::Entity entity;
	TypeA* p1;
	TypeB* p2;
	TypeC* p3;
	TypeD* p4;
	TypeE* p5;
	TypeF* p6;
	TypeG* p7;
	TypeH* p8;
}

fn bool query_iter_next(QueryIterBase* self) @private
{
	while (self.archetype_idx < self.world.archetypes_len)
	{
		Archetype* arch = self.world.archetypes[self.archetype_idx];

		// Match checks only need to happen when we first enter an archetype.
		if (self.row_idx == 0)
		{
			bool match = true;
			for (ushort i = 0; i < self.include_len; i++)
			{
				if (arch.find_column(self.include_types[i]) < 0)
				{
					match = false;
					break;
				}
			}
			if (match)
			{
				for (ushort i = 0; i < self.exclude_len; i++)
				{
					if (arch.find_column(self.exclude_types[i]) >= 0)
					{
						match = false;
						break;
					}
				}
			}

			if (!match)
			{
				self.archetype_idx++;
				continue;
			}
		}
		
		// If we are at the end of this archetype, move to next
		if (self.row_idx >= arch.len)
		{
			self.archetype_idx++;
			self.row_idx = 0;
			continue;
		}
		
		// Found a valid row!
		return true;
	}
	return false;
}


<*
Query the world for entities that match the specified component types and filters. The query returns an iterator that can be used to iterate over the matching entities and their components.
*>
macro World.query(World* self, ...)
{
	// TODO: make Query filters extensible so that custom filters can be added in the future. For now, we only support With and Without filters.
	int $found = 0;
	bool $filter_seen = false;
	$for var $j = 0; $j < $vaarg.len; $j++:
		String $name = ecs::type_to_name($vaarg[$j]);
		$if $name == "void":
			// Skip void
		$else
			$if $name.len >= 5:
				$if $name[0..4] == "With{":
					$filter_seen = true;
				$else
					$if $name.len >= 8:
						$if $name[0..7] == "Without{":
							$filter_seen = true;
						$else
							$if $filter_seen:
								$error "all With/Without filters must be placed after the components to return";
							$endif
							$found = $found + 1;
						$endif
					$else
						$if $filter_seen:
							$error "all With/Without filters must be placed after the components to return";
						$endif
						$found = $found + 1;
					$endif
				$endif
			$else
				$if $filter_seen:
					$error "all With/Without filters must be placed after the components to return";
				$endif
				$found = $found + 1;
			$endif
		$endif
	$endfor

	$if $found == 1:
		QueryIter{$vaarg[0], void, void, void, void, void, void, void} iter = {
			.base = { .world = self, .archetype_idx = 0, .row_idx = 0, .include_len = 0, .exclude_len = 0 }
		};
	$else
		$if $found == 2:
			QueryIter{$vaarg[0], $vaarg[1], void, void, void, void, void, void} iter = {
				.base = { .world = self, .archetype_idx = 0, .row_idx = 0, .include_len = 0, .exclude_len = 0 }
			};
		$else
			$if $found == 3:
				QueryIter{$vaarg[0], $vaarg[1], $vaarg[2], void, void, void, void, void} iter = {
					.base = { .world = self, .archetype_idx = 0, .row_idx = 0, .include_len = 0, .exclude_len = 0 }
				};
			$else
				$if $found == 4:
					QueryIter{$vaarg[0], $vaarg[1], $vaarg[2], $vaarg[3], void, void, void, void} iter = {
						.base = { .world = self, .archetype_idx = 0, .row_idx = 0, .include_len = 0, .exclude_len = 0 }
					};
				$else
					$if $found == 5:
						QueryIter{$vaarg[0], $vaarg[1], $vaarg[2], $vaarg[3], $vaarg[4], void, void, void} iter = {
							.base = { .world = self, .archetype_idx = 0, .row_idx = 0, .include_len = 0, .exclude_len = 0 }
						};
					$else
						$if $found == 6:
							QueryIter{$vaarg[0], $vaarg[1], $vaarg[2], $vaarg[3], $vaarg[4], $vaarg[5], void, void} iter = {
								.base = { .world = self, .archetype_idx = 0, .row_idx = 0, .include_len = 0, .exclude_len = 0 }
							};
						$else
							$if $found == 7:
								QueryIter{$vaarg[0], $vaarg[1], $vaarg[2], $vaarg[3], $vaarg[4], $vaarg[5], $vaarg[6], void} iter = {
									.base = { .world = self, .archetype_idx = 0, .row_idx = 0, .include_len = 0, .exclude_len = 0 }
								};
							$else
								QueryIter{$vaarg[0], $vaarg[1], $vaarg[2], $vaarg[3], $vaarg[4], $vaarg[5], $vaarg[6], $vaarg[7]} iter = {
									.base = { .world = self, .archetype_idx = 0, .row_idx = 0, .include_len = 0, .exclude_len = 0 }
								};
							$endif
						$endif
					$endif
				$endif
			$endif
		$endif
	$endif

	int $inc_idx = 0;
	int $exc_idx = 0;
	$for var $j = 0; $j < $vaarg.len; $j++:
		String $name = ecs::type_to_name($vaarg[$j]);
		$if $name == "void":
			// Skip void
		$else
			$if $name.len >= 5:
				$if $name[0..4] == "With{":
					iter.include_types[$inc_idx] = ecs::type_to_typeid(ecs::get_filter_type($vaarg[$j]));
					$inc_idx = $inc_idx + 1;
				$else
					$if $name.len >= 8:
						$if $name[0..7] == "Without{":
							iter.exclude_types[$exc_idx] = ecs::type_to_typeid(ecs::get_filter_type($vaarg[$j]));
							$exc_idx = $exc_idx + 1;
						$else
							$if ecs::type_to_typeid($vaarg[$j]) == ecs::Entity::typeid:
								// Do not add ecs::Entity to include_types
							$else
								iter.include_types[$inc_idx] = ecs::type_to_typeid($vaarg[$j]);
								$inc_idx = $inc_idx + 1;
							$endif
						$endif
					$else
						$if ecs::type_to_typeid($vaarg[$j]) == ecs::Entity::typeid:
							// Do not add ecs::Entity to include_types
						$else
							iter.include_types[$inc_idx] = ecs::type_to_typeid($vaarg[$j]);
							$inc_idx = $inc_idx + 1;
						$endif
					$endif
				$endif
			$else
				$if ecs::type_to_typeid($vaarg[$j]) == ecs::Entity::typeid:
					// Do not add ecs::Entity to include_types
				$else
					iter.include_types[$inc_idx] = ecs::type_to_typeid($vaarg[$j]);
					$inc_idx = $inc_idx + 1;
				$endif
			$endif
		$endif
	$endfor
	iter.cached_archetype_idx = 0xffff_ffff;
	iter.include_len = (ushort)$inc_idx;
	iter.exclude_len = (ushort)$exc_idx;

	return iter;
}

macro QueryIter.next(QueryIter* self)
{
	if (!query_iter_next(&self.base)) return ($Typeof(self))null;
	
	Archetype* arch = self.world.archetypes[self.archetype_idx];
	uint row = self.row_idx;

	if (self.base.cached_archetype_idx != self.base.archetype_idx)
	{
		int $col_slot = 0;
		$foreach $m : $Typeof(*self)::members:
			$if $m.name == "base" || $m.name == "entity":
			$else
				$if $m.type != void*::typeid:
					$if $m.type == ecs::Entity*::typeid:
					$else
						self.base.component_columns[$col_slot] = arch.find_column(ecs::type_to_typeid($Typeof(*(($Typefrom($m.type))1))));
						assert(self.base.component_columns[$col_slot] >= 0);
						$col_slot = $col_slot + 1;
					$endif
				$endif
			$endif
		$endforeach

		self.base.cached_archetype_idx = self.base.archetype_idx;
	}
	
	self.entity = arch.entities[row];
	int $col_read_slot = 0;
	
	$foreach $m : $Typeof(*self)::members:
		$if $m.name == "base" || $m.name == "entity":
		$else
			$if $m.type != void*::typeid:
				{
					$if $m.type == ecs::Entity*::typeid:
						{
							String $member_name = $m.name;
							self.$member_name = &arch.entities[row];
						}
					$else
						int col_idx = self.base.component_columns[$col_read_slot];
						$col_read_slot = $col_read_slot + 1;
						ComponentColumn col = arch.get_column((uint)col_idx);
						String $member_name = $m.name;
						self.$member_name = ecs::cast_ptr($Typeof(*(($Typefrom($m.type))1)), col[row]);
					$endif
				}
			$endif
		$endif
	$endforeach

	self.row_idx = self.row_idx + 1;
	return self;
}

fn void World.enqueue_command(World* self, Command cmd) @export("world_enqueue_command")
{
	self.commands_mutex.lock()!!;
	defer self.commands_mutex.unlock();

	if (self.commands_len >= self.commands_cap)
	{
		uint new_cap = self.commands_cap == 0 ? 16 : self.commands_cap * 2;
		self.commands = alloc::realloc_array(self.allocator, self.commands.ptr, Command, (sz)new_cap);
		self.commands = self.commands.ptr[0..self.commands_len];
		self.commands_cap = new_cap;
	}
	self.commands[self.commands_len] = cmd;
	self.commands_len++;
}

fn ecs::Entity World.deferred_spawn(World* self) @export("world_deferred_spawn")
{
	self.commands_mutex.lock()!!;
	defer self.commands_mutex.unlock();

	ecs::Entity entity;
	if (self.free_records_len > 0)
	{
		uint record_idx = self.free_records[self.free_records_len - 1];
		self.free_records_len--;
		self.free_records = self.free_records.ptr[0..self.free_records_len];
		entity.id = (ulong)record_idx;
		entity.gen = self.entity_records[record_idx].gen;

		self.entity_records[record_idx].active = true;
		self.entity_records[record_idx].archetype = self.empty_archetype;
		self.entity_records[record_idx].row = 0;
	}
	else
	{
		uint record_idx = self.entity_records_len + self.deferred_spawn_count;
		self.deferred_spawn_count++;
		entity.id = (ulong)record_idx;
		entity.gen = 0;
	}

	if (self.commands_len >= self.commands_cap)
	{
		uint new_cap = self.commands_cap == 0 ? 16 : self.commands_cap * 2;
		self.commands = alloc::realloc_array(self.allocator, self.commands.ptr, Command, (sz)new_cap);
		self.commands = self.commands.ptr[0..self.commands_len];
		self.commands_cap = new_cap;
	}
	self.commands[self.commands_len] = {
		.kind = CommandKind.SPAWN,
		.entity = entity,
		.type = void::typeid,
		.data = null,
		.size = 0,
		.deinitializer = null
	};
	self.commands_len++;

	return entity;
}

fn void World.enqueue_add_resource_command(World* self, typeid type, void* data) @export("world_enqueue_add_resource_command")
{
	self.enqueue_command({
		.kind = CommandKind.ADD_RESOURCE,
		.entity = {},
		.type = type,
		.data = data,
		.size = 0,
		.deinitializer = null
	});
}

fn void World.flush_commands(World* self) @export("world_flush_commands")
{
	self.commands_mutex.lock()!!;
	defer self.commands_mutex.unlock();

	if (self.commands_len == 0) return;

	if (self.deferred_spawn_count > 0)
	{
		uint new_len = self.entity_records_len + self.deferred_spawn_count;
		ensure_entity_records_capacity(self, (usz)new_len);

		for (uint i = self.entity_records_len; i < new_len; i++)
		{
			self.entity_records[i] = {
				.archetype = null,
				.row = 0,
				.gen = 0,
				.active = false
			};
		}
		self.entity_records_len = new_len;
		self.entity_records = self.entity_records.ptr[0..new_len];
		self.deferred_spawn_count = 0;
	}

	for (uint i = 0; i < self.commands_len; i++)
	{
		Command* cmd = &self.commands[i];
		switch (cmd.kind)
		{
			case CommandKind.SPAWN:
			{
				ecs::Entity entity = cmd.entity;
				uint row = self.empty_archetype.add_entity(self.allocator, entity);
				self.entity_records[entity.id] = {
					.archetype = self.empty_archetype,
					.row = row,
					.gen = entity.gen,
					.active = true
				};
			}
			case CommandKind.DESPAWN:
			{
				self.despawn(cmd.entity);
			}
			case CommandKind.ADD_COMPONENT:
			{
				self.add_component(cmd.entity, cmd.type, cmd.data);
				if (cmd.data != null)
				{
					alloc::free(self.allocator, cmd.data);
				}
			}
			case CommandKind.REMOVE_COMPONENT:
			{
				self.remove_component(cmd.entity, cmd.type);
			}
			case CommandKind.ADD_RESOURCE:
			{
				self.add_resource_internal(cmd.type, cmd.data, cmd.deinitializer);
			}
		}
	}

	self.commands_len = 0;
}