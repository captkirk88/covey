module ecs;

import world;
import std::core::mem;

alias Deinitializer = fn void(void*, Allocator);

struct ResourceRecord @export("ResourceRecord")
{
	typeid type;
	void* data;
	Deinitializer deinitializer;
}

fn void deinit_wrapper(void* ptr, Allocator allocator)<Type>
{
	Type* actual = (Type*)ptr;
	$if $defined(Type.deinit):
		actual.deinit(allocator);
	$endif
}

fn void World.add_resource_internal(World* self, typeid type, void* data, Deinitializer deinitializer) @export("world_add_resource")
{
	self.remove_resource(type);
	
	if (self.resources_len >= self.resources_cap)
	{
		uint new_cap = self.resources_cap == 0 ? 8 : self.resources_cap * 2;
		self.resources = alloc::realloc_array(self.allocator, self.resources.ptr, ResourceRecord, (sz)new_cap);
		self.resources = self.resources.ptr[0..self.resources_len];
		self.resources_cap = new_cap;
	}
	self.resources[self.resources_len] = { type, data, deinitializer };
	self.resources_len++;
}

fn void World.remove_resource(World* self, typeid type) @export("world_remove_resource")
{
	for (uint i = 0; i < self.resources_len; i++)
	{
		if (self.resources[i].type == type)
		{
			if (self.resources[i].deinitializer != null)
			{
				self.resources[i].deinitializer(self.resources[i].data, self.allocator);
			}
			if (self.resources[i].data != null)
			{
				alloc::free(self.allocator, self.resources[i].data);
			}
			for (uint j = i; j < self.resources_len - 1; j++)
			{
				self.resources[j] = self.resources[j + 1];
			}
			self.resources_len--;
			self.resources = self.resources.ptr[0..self.resources_len];
			return;
		}
	}
}

fn bool World.has_resource(World* self, typeid type) @export("world_has_resource")
{
	for (uint i = 0; i < self.resources_len; i++)
	{
		if (self.resources[i].type == type)
		{
			return true;
		}
	}
	return false;
}

fn void* World.get_resource(World* self, typeid type) @export("world_get_resource")
{
	for (uint i = 0; i < self.resources_len; i++)
	{
		if (self.resources[i].type == type)
		{
			return self.resources[i].data;
		}
	}
	return null;
}

fn void World.clear_resources(World* self) @export("world_clear_resources")
{
	for (uint i = 0; i < self.resources_len; i++)
	{
		if (self.resources[i].deinitializer != null)
		{
			self.resources[i].deinitializer(self.resources[i].data, self.allocator);
		}
		if (self.resources[i].data != null)
		{
			alloc::free(self.allocator, self.resources[i].data);
		}
	}
	if (self.resources.ptr != null)
	{
		alloc::free(self.allocator, self.resources.ptr);
		self.resources = {};
	}
	self.resources_len = 0;
	self.resources_cap = 0;
}

macro void World.add_resource(World* self, ...)
{
	$if $vaarg.len == 1:
		{
			$if $Typeof($vaarg[0])::kind == TypeKind.POINTER:
				{
					$Typefrom($Typeof(*$vaarg[0]))* heap_copy = alloc::malloc(self.allocator, $Typeof(*$vaarg[0])::size);
					*heap_copy = *$vaarg[0];
					self.add_resource_internal($Typeof(*$vaarg[0])::typeid, (void*)heap_copy, &deinit_wrapper{$Typeof(*$vaarg[0])});
				}
			$else
				{
					$Typefrom($Typeof($vaarg[0]))* heap_copy = alloc::malloc(self.allocator, $Typeof($vaarg[0])::size);
					*heap_copy = $vaarg[0];
					self.add_resource_internal($Typeof($vaarg[0])::typeid, (void*)heap_copy, &deinit_wrapper{$Typeof($vaarg[0])});
				}
			$endif
		}
	$else
		{
			$if $Typeof($vaarg[1])::kind == TypeKind.POINTER:
				{
					$Typefrom($Typeof(*$vaarg[1]))* heap_copy = alloc::malloc(self.allocator, $Typeof(*$vaarg[1])::size);
					*heap_copy = *$vaarg[1];
					self.add_resource_internal($Typeof(*$vaarg[1])::typeid, (void*)heap_copy, &deinit_wrapper{$Typeof(*$vaarg[1])});
				}
			$else
				{
					$Typefrom($Typeof($vaarg[1]))* heap_copy = alloc::malloc(self.allocator, $Typeof($vaarg[1])::size);
					*heap_copy = $vaarg[1];
					self.add_resource_internal($Typeof($vaarg[1])::typeid, (void*)heap_copy, &deinit_wrapper{$Typeof($vaarg[1])});
				}
			$endif
		}
	$endif
}
