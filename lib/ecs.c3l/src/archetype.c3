module archetype;
import ecs;
import std;
import std::core::mem;

<*
 An archetype is a collection of entities that share the same set of components. It is used to optimize the storage and retrieval of entities in an ECS (Entity Component System) architecture. Each archetype can be thought of as a "table" where each row represents an entity and each column represents a component type. By grouping entities with the same components together, we can improve cache locality and reduce the overhead of managing entities and their components.
*>
struct Archetype @export("Archetype")
{
	typeid[] component_types;
	sz[] component_sizes;
	void*[] columns; // Array of pointers, each pointing to a contiguous component buffer
	ecs::Entity[] entities;
	uint len;
	uint cap;
}

fn Archetype new(typeid[] types, Allocator allocator) @export("archetype_new")
{
	Archetype self = { };
	self.len = 0;
	self.cap = 0;
	self.component_types = mem::@clone_slice(types);
	self.component_sizes = alloc::alloc_array(allocator, sz, types.len);
	self.columns = alloc::alloc_array(allocator, void*, types.len);
	self.entities = { };

	for (uint i = 0; i < types.len; i++)
	{
		self.component_sizes[i] = types[i].size;
		self.columns[i] = null;
	}
	return self;
}

<*
 Frees all memory associated with the archetype.
*>
fn void Archetype.deinit(Archetype* self, Allocator allocator) @export("archetype_deinit")
{
	for (uint i = 0; i < self.component_types.len; i++)
	{
		if (self.columns[i] != null) alloc::free(allocator, self.columns[i]);
	}

	alloc::free(allocator, self.entities.ptr);
	alloc::free(allocator, self.columns.ptr);
	alloc::free(allocator, self.component_sizes.ptr);
	alloc::free(allocator, self.component_types.ptr);
	*self = { };
}

<*
 Resizes all component columns to ensure capacity.
*>
fn void ensure_capacity(Archetype* self, Allocator allocator, usz new_cap) @private
{
	if (new_cap <= self.cap) return;
	if (new_cap < 8)
	{
		new_cap = 8;
	}
	else if (new_cap < (usz)self.cap * 2)
	{
		new_cap = (usz)self.cap * 2;
	}

	self.entities = alloc::realloc_array(allocator, self.entities.ptr, ecs::Entity, (sz)new_cap);

	for (uint i = 0; i < self.component_types.len; i++)
	{
		self.columns[i] = alloc::realloc(allocator, self.columns[i], self.component_sizes[i] * (sz)new_cap);
	}
	self.cap = (uint)new_cap;
}

<*
 Adds an entity entry to the table. Returns the row index.
*>
fn uint Archetype.add_entity(Archetype* self, Allocator allocator, ecs::Entity entity) @export("archetype_add_entity")
{
	if (self.len == self.cap)
	{
		ensure_capacity(self, allocator, (usz)self.cap + 1);
	}

	uint index = self.len;
	self.entities[index] = entity;
	self.len++;
	return index;
}

<*
 Removes an entity via "swap-and-pop".

Returns the Entity ID of the one that was moved into the deleted slot.
*>
fn ecs::Entity Archetype.remove_at(Archetype* self, uint index) @export("archetype_remove_at")
{
	assert(index < self.len);
	uint last_index          = self.len - 1;
	ecs::Entity moved_entity = self.entities[last_index];

	if (index != last_index)
	{
		// Swap the entity ID
		self.entities[index] = moved_entity;

		// Swap component data across all columns
		for (uint i = 0; i < self.component_types.len; i++)
		{
			void* col = self.columns[i];
			sz size   = self.component_sizes[i];
			char* dst = (char*)col + (index * size);
			char* src = (char*)col + (last_index * size);
			mem::copy(dst, src, (usz)size);
		}
	}

	self.len--;
	return moved_entity;
}

struct ComponentColumn @export("ComponentColumn")
{
	void* data;
	sz size;
	uint column;
}

fn void* ComponentColumn.idx(ComponentColumn self, usz index) @operator([])
{
	return self.data + (index * (usz)self.size);
}

<*
Helper to retrieve the component column wrapper.
*>
fn ComponentColumn Archetype.get_column(Archetype* self, uint column_index) @export("archetype_get_column")
{
	ComponentColumn res = { self.columns[column_index], self.component_sizes[column_index], column_index };
	return res;
}

fn int Archetype.find_column(Archetype* self, typeid type) @export("archetype_find_column")
{
	for (uint i = 0; i < self.component_types.len; i++)
	{
		if (self.component_types[i] == type) return (int)i;
	}
	return -1;
}

fn typeid Archetype.get_component_type_(Archetype* self, ComponentColumn* column) @export("archetype_get_component_type")
{
	return self.component_types[column.column];
}

<*
Check if the archetype matches the given set of component types. Returns `true` if the archetype contains all the specified component types, `false` otherwise.
*>
fn bool Archetype.matches(Archetype* self, typeid... types) @export("archetype_matches")
{
	for (uint i = 0; i < types.len; i++)
	{
		if (self.find_column(types[i]) < 0) return false;
	}
	return true;
}

fn ComponentType* get(Archetype* self, uint col, uint row)<ComponentType>
{
	return (ComponentType*)self.get_column(col)[row];
}

struct ArchetypeStorage @export("ArchetypeStorage")
{
	Archetype[] archetypes;
}
